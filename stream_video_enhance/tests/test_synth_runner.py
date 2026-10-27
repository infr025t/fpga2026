"""Diagnostics must reject a misleading success marker and missing evidence."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from run_core_synth import check_diagnostics, check_metrics

class DiagnosticsTests(unittest.TestCase):
    def test_clean(self):
        self.assertEqual(check_diagnostics('PASS SYNTH\n', 0), [])
    def test_error_after_pass(self):
        self.assertTrue(check_diagnostics('PASS SYNTH\nERROR: failed', 0))
    def test_critical_warning(self):
        self.assertTrue(check_diagnostics('CRITICAL WARNING: timing\nPASS SYNTH', 0))
    def test_absent_marker(self):
        self.assertTrue(check_diagnostics('normal exit', 0))
    def test_tcl_echo_is_not_completion(self):
        self.assertTrue(check_diagnostics('# puts "PASS SYNTH"\n', 0))
    def test_exit(self):
        self.assertTrue(check_diagnostics('PASS SYNTH', 1))
    def test_timeout(self):
        self.assertTrue(check_diagnostics('PASS SYNTH', None))
    def test_actual_timing_failure_rejected(self):
        metrics=dict(RAMB18=5,RAMB36=5,DSP=18,LUT=2339,FF=2586,latches=0,
                     multidrivers=0,combinational_loops=0,registered_setup_slack_ns=-0.391,
                     overall_setup_slack_ns=-0.391,unconstrained_internal_endpoints=0,
                     registered_hold_slack_ns=0.2,no_input_delay=0,no_output_delay=0,no_clock=0)
        self.assertIn('registered timing',check_metrics(metrics,'guided_core'))
        metrics['registered_setup_slack_ns']=1
        metrics['overall_setup_slack_ns']=1
        self.assertEqual(check_metrics(metrics,'guided_core'),[])
        metrics['registered_hold_slack_ns']=-0.1
        self.assertIn('registered hold',check_metrics(metrics,'guided_core'))
        metrics['registered_hold_slack_ns']=0.2
        metrics['DSP']=25
        self.assertIn('DSP cap',check_metrics(metrics,'guided_core'))
        metrics['DSP']=18;metrics['unconstrained_internal_endpoints']=1
        self.assertIn('unconstrained_internal_endpoints',check_metrics(metrics,'guided_core'))

if __name__ == '__main__': unittest.main()
