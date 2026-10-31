"""Encoding checks use simulated records, never participant data."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("encode_session", ROOT / "tools/encode_session.py")
E = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(E)


def completed(**overrides):
    row = dict(video_status="completed", video_file="SIMULATED.mkv", video_start_frame="60",
               video_target_frame="180", frame_rate="60", retrieval_time_s="", total_tab_switches="1",
               incorrect_selections="0", first_selection_correct="1", no_selection="0", technical_loss="0", coder="TEST")
    return {**row, **overrides}


class VideoTests(unittest.TestCase):
    def test_frames_compute_rt_and_preserve_zero_errors(self):
        row = E.video_values(completed())
        self.assertEqual(row["retrieval_time_s"], 2)
        self.assertEqual(row["incorrect_selections"], 0)

    def test_wrong_first_then_correct(self):
        row = E.video_values(completed(total_tab_switches="2", incorrect_selections="1", first_selection_correct="0"))
        self.assertEqual(row["first_selection_correct"], 0)

    def test_inconsistent_counts_rejected(self):
        for kwargs in (dict(incorrect_selections="1"), dict(first_selection_correct="0"), dict(total_tab_switches="0")):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                E.video_values(completed(**kwargs))

    def test_incomplete_rt_cannot_be_filled(self):
        with self.assertRaises(ValueError): E.video_values(completed(video_status="timeout"))

    def test_observable_timeout_with_errors(self):
        r = completed(video_status="timeout", video_target_frame="", total_tab_switches="2",
                      incorrect_selections="2", first_selection_correct="0")
        result = E.video_values(r)
        self.assertIsNone(result["retrieval_time_s"])
        self.assertEqual(result["no_selection"], 0)

    def test_true_no_selection_keeps_first_accuracy_missing(self):
        r = completed(video_status="timeout", video_target_frame="", total_tab_switches="0",
                      incorrect_selections="0", first_selection_correct="", no_selection="1")
        result = E.video_values(r)
        self.assertIsNone(result["first_selection_correct"])

    def test_break_can_have_no_technical_loss(self):
        r = completed(video_status="interrupted", video_target_frame="", total_tab_switches="0",
                      incorrect_selections="0", first_selection_correct="", no_selection="1")
        self.assertEqual(E.video_values(r)["technical_loss"], 0)

    def test_frame_disagreement_rejected(self):
        with self.assertRaises(ValueError): E.video_values(completed(retrieval_time_s="4"))

    def test_nonfinite_and_negative_rejected(self):
        for value in ("nan", "inf", "-1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                E.video_values(completed(frame_rate=value))

    def test_fractional_rate_supported(self):
        r = E.video_values(completed(frame_rate="59.94"))
        self.assertAlmostEqual(r["retrieval_time_s"], 120/59.94)

    def test_missing_or_unreviewed_data_not_promoted(self):
        self.assertEqual(E.video_values({})["video_verified"], 0)
        with self.assertRaises(ValueError): E.video_values({"retrieval_time_s": "1.5"})

    def test_coder_and_recording_are_required(self):
        for field in ("coder", "video_file"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                E.video_values(completed(**{field: ""}))


class ExportTests(unittest.TestCase):
    def test_missing_terminal_outcome_is_unknown_not_unexposed(self):
        with tempfile.TemporaryDirectory() as folder:
            run = Path(folder)/"run";run.mkdir()
            meta = dict(session_id="SIM",participant="TEST",group=1,mode="test",plan=[dict(
                name="H-L",orientation="H",tabLoad="low",contentSet="A",expectedTabCount=6,
                taskOrder=["a.html"],trials=[dict(id="T1",targetID="P1",targetTitle="A",path="a.html")])])
            (run/"session.json").write_text(json.dumps(meta))
            E.write_csv(run/"trials_aux.csv",[],list(E.IDENTITY)+["status"])
            E.prepare(run,Path(folder)/"coding")
            row=E.read_csv(Path(folder)/"coding/video_coding.csv")[0]
            self.assertEqual(row["controller_status"],"no_terminal_outcome")
            self.assertEqual(row["video_status"],"")

    def test_complete_prepare_and_export_never_uses_automatic_estimates(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            run, coding, out = root/"run", root/"coding", root/"export"
            run.mkdir()
            meta = dict(session_id="SIM",participant="TEST",group=1,mode="test",plan=[dict(
                name="H-L",orientation="H",tabLoad="low",contentSet="A",expectedTabCount=6,
                taskOrder=["a.html","b.html"],trials=[
                    dict(id="T1",targetID="P1",targetTitle="A",path="a.html"),
                    dict(id="T2",targetID="P2",targetTitle="B",path="b.html"),
                    dict(id="T3",targetID="P1",targetTitle="A",path="a.html")])])
            (run/"session.json").write_text(json.dumps(meta))
            schedule = E.scheduled(meta)
            raw = [{**r,"status":"completed_auto","auto_detection_elapsed_s":123} for r in schedule]
            E.write_csv(run/"trials_aux.csv",raw,list(raw[0]))
            E.prepare(run,coding)
            # An unreviewed session exports missing performance, not 123-second RTs.
            E.export(run,coding,out)
            blank = E.read_csv(out/"analysis_trials.csv")
            self.assertEqual(blank[0]["retrieval_time_s"],"")
            rows = E.read_csv(coding/"video_coding.csv")
            rows[0].update(completed())
            rows[1].update(completed(video_status="timeout",video_target_frame="",total_tab_switches="2",
                                      incorrect_selections="2",first_selection_correct="0"))
            (coding/"video_coding.csv").unlink()
            E.write_csv(coding/"video_coding.csv",rows,list(rows[0]))
            E.export(run,coding,root/"export2")
            result = E.read_csv(root/"export2/condition_summary.csv")[0]
            self.assertEqual(result["completed_rt_n"],"1")
            self.assertEqual(result["mean_retrieval_time_s"],"2.0")
            self.assertEqual(result["first_selection_error_rate"],"0.5")
            self.assertEqual(result["timeouts"],"1")
            self.assertEqual(result["uncoded_trials"],"1")
            joins=E.read_csv(root/"export2/survey_join_keys.csv")
            self.assertEqual(len(joins),1)
            self.assertEqual(joins[0]["participant"],"TEST")
            self.assertEqual(joins[0]["condition"],"H-L")
            self.assertEqual(E.read_csv(root/"export2/analysis_trials.csv")[2]["is_repeat"],"1")
            self.assertEqual(E.read_csv(run/"trials_aux.csv")[0]["auto_detection_elapsed_s"],"123")
            with self.assertRaises(FileExistsError): E.prepare(run,coding)

    def test_duplicate_or_mismatched_trials_rejected(self):
        expected=[dict(block=1,trial="T1",participant="A")]
        with self.assertRaises(ValueError): E.indexed([dict(block="1",trial="T1",participant="B")],expected,{})
        with self.assertRaises(ValueError): E.indexed([expected[0],expected[0]],expected,{})


if __name__ == "__main__": unittest.main()
