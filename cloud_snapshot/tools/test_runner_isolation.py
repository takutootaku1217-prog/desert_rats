import importlib.util, pathlib, tempfile, unittest, os, json, sys
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('runner', pathlib.Path(__file__).with_name('run_prototype_checks.py'));runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
class Isolation(unittest.TestCase):
 def test_both_platforms_are_confined(self):
  with tempfile.TemporaryDirectory() as home:
   env=runner.make_test_env(home)
   for key in ['HOME','USERPROFILE','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME','APPDATA','LOCALAPPDATA']:
    self.assertTrue(pathlib.Path(env[key]).is_relative_to(pathlib.Path(home)))
    self.assertTrue(pathlib.Path(env[key]).is_dir())
   self.assertEqual(env['FLUID_TEST_HOME'], home)
   self.assertEqual(env.get('PATH'),os.environ.get('PATH'))
 def test_cleanup_retry_and_status_are_reported_separately(self):
  class TransientCleanup:
   def __init__(self): self.calls=0
   def cleanup(self):
    self.calls+=1
    if self.calls==1: raise OSError(145,'directory not empty')
  transient=TransientCleanup()
  recovered=runner.cleanup_temporary(transient,retries=2,retry_delay=0)
  self.assertTrue(recovered['ok'])
  self.assertEqual(recovered['attempts'],2)
  self.assertEqual(transient.calls,2)
  class StuckCleanup:
   def cleanup(self): raise OSError(145,'directory not empty')
  warning=runner.cleanup_temporary(StuckCleanup(),retries=1,retry_delay=0)
  self.assertFalse(warning['ok'])
  self.assertEqual(warning['attempts'],1)
  self.assertIn('WinError 145' if os.name=='nt' else 'OSError',warning['error'])
  self.assertIn('directory not empty',warning['error'])
  self.assertEqual(runner.runner_exit_code([{'exit':0}],recovered),0)
  self.assertEqual(runner.runner_exit_code([{'exit':0}],warning),2)
  self.assertEqual(runner.runner_exit_code([{'exit':1}],warning),1)
  payload=runner.result_payload([{'test':'import','exit':0}],warning)
  self.assertFalse(payload['cleanup']['ok'])
  self.assertEqual(payload['cleanup']['error'],warning['error'])
  self.assertEqual(payload['results'][0]['test'],'import')
 def test_launch_error_preserves_result_and_stops_without_retry(self):
  # Mock only the process boundary: exercise real CLI, files, env and cleanup.
  for error in [FileNotFoundError(2, 'missing engine'), PermissionError(13, 'launch denied')]:
   with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as temp:
    out=pathlib.Path(temp)/'results'
    code=None
    with patch.object(sys,'argv',['runner','--output',str(out)]), patch.object(runner.subprocess,'run',side_effect=error) as launch:
     try: code=runner.main()
     except OSError: pass
    self.assertTrue((out/'results.json').is_file(), 'launch failure must preserve results.json')
    payload=json.loads((out/'results.json').read_text())
    self.assertEqual(code,1)
    self.assertEqual(launch.call_count,1, 'never retry a denied launch or continue to other cases')
    self.assertEqual(len(payload['results']),1)
    self.assertEqual(payload['results'][0]['test'],'import')
    self.assertEqual(payload['results'][0]['launch_error'],type(error).__name__)
    self.assertEqual(payload['results'][0]['exit'],127 if isinstance(error,FileNotFoundError) else 126)
    self.assertTrue(payload['cleanup']['ok'])
    self.assertIn(str(error),(out/'import.log').read_text())
    self.assertTrue((out/'source_manifest.json').is_file())
 def test_later_launch_failure_keeps_earlier_success(self):
  with tempfile.TemporaryDirectory() as temp:
   out=pathlib.Path(temp)/'results'
   success=runner.subprocess.CompletedProcess([],0,b'import complete\n')
   with patch.object(sys,'argv',['runner','--output',str(out)]), patch.object(runner.subprocess,'run',side_effect=[success,PermissionError(13,'launch denied')]) as launch:
    code=runner.main()
   payload=json.loads((out/'results.json').read_text())
   self.assertEqual(code,1)
   self.assertEqual(launch.call_count,2)
   self.assertEqual([r['exit'] for r in payload['results']],[0,126])
   self.assertEqual(payload['results'][0]['test'],'import')
   self.assertEqual(payload['results'][1]['test'],runner.TESTS[0])
   self.assertEqual((out/'import.log').read_text(),'import complete\n')
   self.assertEqual(payload['results'][1]['launch_error'],'PermissionError')
 def test_payload_records_actual_host_not_a_fixed_os_claim(self):
  payload=runner.result_payload([],{'ok':True})
  self.assertEqual(payload.get('host_platform'),sys.platform)
  self.assertNotIn('Linux headless',payload['scope'])
 def test_long_case_default_is_bounded_and_cli_override_wins(self):
  # Only the subprocess boundary is mocked; real CLI selection, output files
  # and cleanup execute. An unchanged 120-second default fails the first row.
  for args,expected in [([], [120,300,120]),(['--timeout','45'], [45,45,45])]:
   with tempfile.TemporaryDirectory() as temp:
    out=pathlib.Path(temp)/'results'
    success=runner.subprocess.CompletedProcess([],0,b'pass\n')
    with patch.object(sys,'argv',['runner','--output',str(out)]+args), patch.object(runner,'TESTS',['land_operation_readiness','site_transfer_contract']), patch.object(runner,'EXTRA_CASES',[]), patch.object(runner.subprocess,'run',return_value=success) as launch:
     code=runner.main()
    self.assertEqual(code,0)
    self.assertEqual([call.kwargs['timeout'] for call in launch.call_args_list],expected)
    self.assertTrue(json.loads((out/'results.json').read_text())['cleanup']['ok'])
if __name__=='__main__':unittest.main()
