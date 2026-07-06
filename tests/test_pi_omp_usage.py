import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


_USAGE_PATH = Path(__file__).resolve().parents[1] / "usage.30s.py"
_TIMESTAMP = "2026-07-06T12:34:56"
_DAY = "2026-07-06"


def load_usage_module(temp_home):
    spec = importlib.util.spec_from_file_location("usage_30s_under_test", _USAGE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    home = str(temp_home)
    module.HOME = home
    module.PI_AGENT_DIR = os.path.join(home, ".pi", "agent")
    module.PI_SESSION_DIR = os.path.join(module.PI_AGENT_DIR, "sessions")
    module.OMP_SESSION_DIR = os.path.join(home, ".omp", "agent", "sessions")
    module._SCAN_CACHE_FILE = os.path.join(home, "scan-cache.json")
    return module


def write_jsonl(path, records):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for record in records:
            fh.write(json.dumps(record, separators=(",", ":")) + "\n")


def session_record(session_id, cwd):
    return {"type": "session", "id": session_id, "cwd": cwd}


def assistant_record(model="gpt-5.5", provider="openai", usage=None):
    return {
        "type": "message",
        "timestamp": _TIMESTAMP,
        "message": {
            "role": "assistant",
            "provider": provider,
            "model": model,
            "usage": usage or {},
        },
    }


def empty_bounds(module):
    return module.range_bounds()


class PiOmpUsageTests(unittest.TestCase):
    def test_default_omp_root_counts_reasoning_tokens_authoritative_cost_and_project_cache(self):
        """OMP JSONL under ~/.omp/agent/sessions is counted as Pi usage with reasoningTokens and cwd."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            project = os.path.join(td, "work", "omp-project")
            omp_file = os.path.join(td, ".omp", "agent", "sessions", "encoded-project", "omp-session.jsonl")
            omp_cache_path = os.path.realpath(omp_file)
            write_jsonl(
                omp_file,
                [
                    session_record("omp-session-1", project),
                    assistant_record(
                        usage={
                            "input": 1_000_000,
                            "output": 2_000_000,
                            "cacheRead": 30,
                            "cacheWrite": 40,
                            "reasoningTokens": 50,
                            "cost": {"total": 0.42, "input": 99.0, "output": 88.0},
                        }
                    ),
                ],
            )

            cache = {}
            result = module.scan_pi(empty_bounds(module), cache)
            all_range = result["ranges"]["all"]

            self.assertEqual(1_000_000, all_range["in"])
            self.assertEqual(2_000_000, all_range["out"])
            self.assertEqual(30, all_range["cr"])
            self.assertEqual(40, all_range["cw"])
            self.assertEqual(50, all_range["reason"])
            self.assertEqual(3_000_120, module.token_total(all_range))
            self.assertAlmostEqual(0.42, all_range["cost"])
            self.assertEqual({"omp-session-1"}, all_range["sessions"])

            self.assertEqual([omp_cache_path], sorted(cache["pi"].keys()))
            entry = cache["pi"][omp_cache_path]
            self.assertEqual(project, entry["proj"])
            self.assertEqual("omp-session-1", entry["sid"])
            self.assertEqual(50, entry["days"][_DAY]["reason"])
            self.assertAlmostEqual(0.42, entry["days"][_DAY]["cost"])

            model_usage = all_range["models"]["openai/gpt-5.5"]
            self.assertEqual(1_000_000, model_usage["in"])
            self.assertEqual(2_000_000, model_usage["out"])
            self.assertEqual(50, model_usage["reason"])
            self.assertAlmostEqual(0.42, model_usage["cost"])

            with mock.patch("builtins.open", side_effect=AssertionError("unchanged cached session was reopened")):
                cached_result = module.scan_pi(empty_bounds(module), cache)
            self.assertEqual(3_000_120, module.token_total(cached_result["ranges"]["all"]))
            self.assertEqual({"omp-session-1"}, cached_result["ranges"]["all"]["sessions"])

            module.compute = lambda: None
            module._load_scan_cache = lambda: cache
            module._detect_local_servers = lambda project_paths: {}
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                module.projects()
            projects = json.loads(stdout.getvalue())

            self.assertEqual(1, len(projects))
            self.assertEqual(project, projects[0]["path"])
            self.assertEqual("omp-project", projects[0]["name"])
            self.assertEqual(1, projects[0]["sessions"])
            self.assertEqual(3_000_120, projects[0]["tokens"])
            self.assertEqual(0.42, projects[0]["cost"])
            self.assertEqual("Gpt 5.5 (Pi)", projects[0]["top_model"])
            self.assertEqual(["pi"], projects[0]["tools"])

    def test_pi_only_root_still_parses_existing_reasoning_when_omp_root_is_missing(self):
        """Legacy Pi sessions remain countable when ~/.omp is absent, including existing reasoning fields."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            pi_file = os.path.join(td, ".pi", "agent", "sessions", "project", "pi-session.jsonl")
            pi_cache_path = os.path.realpath(pi_file)
            write_jsonl(
                pi_file,
                [
                    session_record("pi-session-1", os.path.join(td, "work", "pi-project")),
                    assistant_record(
                        model="claude-sonnet-4.6",
                        provider="anthropic",
                        usage={
                            "input": 11,
                            "output": 22,
                            "cacheRead": 3,
                            "cacheWrite": 4,
                            "reasoning": 5,
                            "cost": {"total": 0.12},
                        },
                    ),
                ],
            )

            cache = {}
            result = module.scan_pi(empty_bounds(module), cache)
            all_range = result["ranges"]["all"]

            self.assertEqual(11, all_range["in"])
            self.assertEqual(22, all_range["out"])
            self.assertEqual(3, all_range["cr"])
            self.assertEqual(4, all_range["cw"])
            self.assertEqual(5, all_range["reason"])
            self.assertEqual(45, module.token_total(all_range))
            self.assertAlmostEqual(0.12, all_range["cost"])
            self.assertEqual({"pi-session-1"}, all_range["sessions"])
            self.assertEqual([pi_cache_path], sorted(cache["pi"].keys()))
            self.assertEqual(5, cache["pi"][pi_cache_path]["days"][_DAY]["reason"])
            self.assertIn("anthropic/claude-sonnet-4.6", all_range["models"])

    def test_pi_usage_reasoning_fallback_is_first_present_not_first_truthy(self):
        """A zero reasoning value wins over later aliases; reasoningTokens counts only when earlier fields are absent."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            pi_file = os.path.join(td, ".pi", "agent", "sessions", "project", "pi-reasoning.jsonl")
            write_jsonl(
                pi_file,
                [
                    session_record("pi-reasoning-fallback", os.path.join(td, "work", "pi-project")),
                    assistant_record(
                        model="first-present-zero",
                        usage={"input": 1, "reasoning": 0, "reasoningTokens": 50},
                    ),
                    assistant_record(
                        model="tokens-only",
                        usage={"input": 2, "reasoningTokens": 50},
                    ),
                ],
            )

            result = module.scan_pi(empty_bounds(module), {})
            all_range = result["ranges"]["all"]

            self.assertEqual(3, all_range["in"])
            self.assertEqual(50, all_range["reason"])
            self.assertEqual(0, all_range["models"]["openai/first-present-zero"]["reason"])
            self.assertEqual(50, all_range["models"]["openai/tokens-only"]["reason"])

    def test_missing_pi_and_omp_roots_are_empty_sources(self):
        """Absent Pi-family session roots produce empty Pi buckets instead of errors or phantom cache data."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            cache = {}

            result = module.scan_pi(empty_bounds(module), cache)

            self.assertEqual({}, cache["pi"])
            for bucket in result["ranges"].values():
                self.assertEqual(0, bucket["in"])
                self.assertEqual(0, bucket["out"])
                self.assertEqual(0, bucket["cr"])
                self.assertEqual(0, bucket["cw"])
                self.assertEqual(0, bucket["reason"])
                self.assertEqual(0.0, bucket["cost"])
                self.assertEqual(set(), bucket["sessions"])
                self.assertEqual({}, bucket["models"])

    def test_duplicate_resolved_roots_do_not_double_count_same_session_file(self):
        """The same real session directory reached through multiple configured roots counts one session once."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            real_root = os.path.join(td, "real-sessions")
            alias_root = os.path.join(td, "alias-sessions")
            pi_agent = os.path.join(td, "pi-agent")
            os.makedirs(real_root, exist_ok=True)
            os.symlink(real_root, alias_root)
            os.makedirs(pi_agent, exist_ok=True)
            os.symlink(real_root, os.path.join(pi_agent, "sessions"))
            module.PI_SESSION_DIR = alias_root
            module.PI_AGENT_DIR = pi_agent
            module.OMP_SESSION_DIR = os.path.join(td, "missing-omp", "sessions")

            session_file = os.path.join(real_root, "project", "session.jsonl")
            write_jsonl(
                session_file,
                [
                    session_record("duplicate-root-session", os.path.join(td, "work", "dup-project")),
                    assistant_record(usage={"input": 7, "output": 8, "cacheRead": 9, "cacheWrite": 10, "reason": 11, "cost": {"total": 0.07}}),
                ],
            )

            cache = {}
            result = module.scan_pi(empty_bounds(module), cache)
            all_range = result["ranges"]["all"]

            self.assertEqual(7, all_range["in"])
            self.assertEqual(8, all_range["out"])
            self.assertEqual(9, all_range["cr"])
            self.assertEqual(10, all_range["cw"])
            self.assertEqual(11, all_range["reason"])
            self.assertEqual(45, module.token_total(all_range))
            self.assertAlmostEqual(0.07, all_range["cost"])
            self.assertEqual({"duplicate-root-session"}, all_range["sessions"])
            self.assertEqual(1, len(cache["pi"]))

    def test_scan_cache_version_mismatch_drops_stale_pi_summaries(self):
        """A changed scan-cache version invalidates old Pi summaries so changed usage parsing is not hidden."""
        with tempfile.TemporaryDirectory() as td:
            module = load_usage_module(Path(td))
            with open(module._SCAN_CACHE_FILE, "w", encoding="utf-8") as fh:
                json.dump(
                    {
                        "v": module._SCAN_CACHE_VERSION - 1,
                        "pi": {
                            "/stale/session.jsonl": {
                                "sig": "old",
                                "days": {_DAY: {"in": 1, "out": 1, "cr": 1, "cw": 1, "reason": 0, "cost": 0.0, "models": {}}},
                                "proj": "/stale",
                                "sid": "stale-session",
                            }
                        },
                    },
                    fh,
                )

            cache = module._load_scan_cache()

            self.assertEqual(module._SCAN_CACHE_VERSION, cache["v"])
            self.assertTrue(cache["_dirty"])
            self.assertNotIn("pi", cache)


if __name__ == "__main__":
    unittest.main()
