#!/usr/bin/env python3
"""Bounded, archive-compatible prototype checks; not the unavailable full core suite."""
import argparse, hashlib, json, os, pathlib, subprocess, sys, tempfile, time
TESTS = '''c_boss_cart_entry c_low_hp_retreat c_low_hp_retreat_owners c_low_hp_retreat_restart npc_fuel_restoration npc_fuel_persistence npc_fuel_restart fuel_depot_ui fuel_depot_restart next_step_guide region_completion region_boss_return region_boss_snapshot region_boss_restart region_boss_boundaries resource_regeneration resource_regeneration_field resource_regeneration_restart c_field_snapshot_capture c_field_snapshot_restart c_field_path_codec c_field_active_owners c_field_active_restart c_field_expiry_owners c_field_expiry_restart c_field_save_ui c_field_save_keyboard c_field_bounded_file c_field_bounded_restart c_expired_recovery c_expired_natural c_expired_restart c_rescue_entry_guidance c_rescue_recreated_runtime c_rescue_natural_persistence c_rescue_natural_restart c_rescue_traces c_rescue_mine_routes c_rescue_mine_ui c_rescue_treatment_persistence c_rescue_treatment_restart c_rescue_ui c_rescue_return c_rescue_approach c_rescue_state_contract land_operation_readiness site_transfer_contract site_transfer_restart guide_success_events guide_return_events guide_events_restart outpost_persistence outpost_persistence_restart first_region_checkpoint first_region_checkpoint_restart first_region_checkpoint_field land_payment_contract first_loop_guide purpose_entry_flow craft_material_routes survival_loop_clarity travel_lane_presentation first_region_mine_arrival_gate first_region_mine_journey_runtime_gate first_town_loop_prototype recovery_town_market_cycle recovery_town_market_restart survival_bed_build_flow normal_haul_frame_progression market_tabs bed_icon full_survival_market_cycle fixed_field_parking canyon_field_tool_kit_v18 canyon_equipment_fixed_parking vehicle_hunt vehicle_hunt_ui vehicle_hunt_survival_cycle c_entry_interaction_v3 c_outpost_entry_v3 field_survival_clock_v3 recovery_frame_upgrade_cycle_v3 field_status_ui_v3_1 attack_only_base_damage_v3_2 meat_icon_variants mine_path_clearance mine_path_ui world_map_route_study world_map_route_study_ui canyon_route_guide'''.split()
TESTS.insert(0, 'land_preview_visibility')
TESTS.insert(0, 'startup_entry_flow')
TESTS[0:0] = ['armor_install_cycle', 'armor_install_restart']
TESTS.insert(0, 'ui_modal_feedback')
TESTS.insert(0, 'region_clear_ui')
TESTS.insert(0, 'next_region_connection')
TESTS.insert(0, 'greenway_salvage')
TESTS.insert(0, 'depot_expedition')
TESTS.insert(0, 'warehouse_rows')
TESTS.insert(0, 'inventory_search')
TESTS.insert(0, 'inventory_selection')
TESTS.insert(0, 'inventory_other_tab_live')
TESTS.insert(0, 'inventory_held_button')
TESTS.insert(0, 'inventory_split_vanish')
TESTS.insert(0, 'expedition_reserved_supplies')
TESTS[0:0] = ['expedition_party_cycle', 'expedition_party_restart']
TESTS[0:0] = ['survival_save_cycle', 'survival_save_restart']
TESTS[0:0] = ['transfer_save_cycle', 'transfer_save_restart']
TESTS[0:0] = ['vehicle_hunt_save_cycle', 'vehicle_hunt_save_restart']
EXTRA_CASES = [('c_outpost_normal_director_v3','normal-director'),('c_outpost_failure_recovery_v3','failure-recovery'),('c_field_hull_failure_v3','hull-failure')]
# Exhaustive real-Main readiness fixtures measured ~142s. Other defaults stay
# at 120s; an explicit CLI timeout continues to override every case.
CASE_TIMEOUTS = {'land_operation_readiness':300}
def make_test_env(home):
 # Both Windows and Unix Godot user-data conventions remain inside this run.
 paths=dict(HOME=home,USERPROFILE=home,XDG_DATA_HOME=home+'/data',XDG_CONFIG_HOME=home+'/config',XDG_CACHE_HOME=home+'/cache',APPDATA=home+'/appdata/roaming',LOCALAPPDATA=home+'/appdata/local')
 for path in paths.values(): pathlib.Path(path).mkdir(parents=True,exist_ok=True)
 return dict(os.environ,**paths,FLUID_TEST_HOME=home)

def cleanup_temporary(tempdir, retries=3, retry_delay=0.25):
 # Godot can finish its last isolated user-data write just after subprocess.run
 # returns on Windows. Retry only the runner-owned temporary directory; never a
 # project, QA, or player save directory.
 attempts=max(1,retries)
 last_error=None
 for attempt in range(attempts):
  try:
   tempdir.cleanup()
   return dict(ok=True,attempts=attempt+1,error=None)
  except OSError as error:
   last_error=error
   if attempt+1 < attempts: time.sleep(retry_delay*(attempt+1))
 code=getattr(last_error,'winerror',None) or getattr(last_error,'errno',None)
 label=('WinError %s' % code) if os.name=='nt' and code else type(last_error).__name__
 return dict(ok=False,attempts=attempts,error='%s: %s' % (label,last_error))

def result_payload(rows, cleanup):
 return dict(
  scope=f'{len(TESTS)+len(EXTRA_CASES)} bounded prototype cases ({len(TESTS)} scripts plus {len(EXTRA_CASES)} outpost variants) plus import; headless, viewport pointer tests are not OS mouse or Windows validation',
  host_platform=sys.platform,
  results=rows,
  cleanup=cleanup,
 )

def runner_exit_code(rows, cleanup):
 if any(row['exit'] for row in rows): return 1
 return 0 if cleanup['ok'] else 2

def main():
 p=argparse.ArgumentParser();p.add_argument('--godot',default='godot');p.add_argument('--output',required=True);p.add_argument('--timeout',type=int,default=None,help='override all case limits (default: 120s, exhaustive readiness case: 300s)');a=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
 manifest={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(root.rglob('*')) if f.is_file() and '.godot' not in f.parts and f.suffix in ('.gd','.tscn','.godot','.png','.svg','.py')}
 (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2))
 rows=[]
 tempdir=tempfile.TemporaryDirectory(prefix='fluid-prototype-qa-')
 try:
  home=tempdir.name
  env=make_test_env(home)
  commands=[('import',[a.godot,'--headless','--path',str(root),'--editor','--import','--quit'])]+[(n,[a.godot,'--headless','--path',str(root),'--script','res://tools/test_'+n+'.gd']) for n in TESTS]+[(name,[a.godot,'--headless','--path',str(root),'--script','res://tools/test_c_outpost_entry_v3.gd','--',arg]) for name,arg in EXTRA_CASES]
  for name,cmd in commands:
   start=time.monotonic()
   launch_error=None
   timeout=a.timeout if a.timeout is not None else CASE_TIMEOUTS.get(name,120)
   try:
    r=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout);code=r.returncode;data=r.stdout
   except subprocess.TimeoutExpired as e: code=124;data=(e.stdout or b'')+b'\nTIMEOUT\n'
   except OSError as e:
    launch_error=type(e).__name__;code=127 if isinstance(e,FileNotFoundError) else 126
    data=('LAUNCH ERROR: %s: %s\n' % (launch_error,e)).encode('utf-8')
   (out/(name+'.log')).write_bytes(data)
   rows.append(dict(test=name,exit=code,seconds=round(time.monotonic()-start,2),timeout=timeout))
   if launch_error is not None: rows[-1]['launch_error']=launch_error
   print(name,code,flush=True)
   # A launch failure/denial is not a test failure; stop rather than retrying
   # the same operation through every remaining case. Preserve evidence below.
   if launch_error is not None: break
 finally:
  cleanup=cleanup_temporary(tempdir)
 (out/'results.json').write_text(json.dumps(result_payload(rows,cleanup),indent=2),encoding='utf-8')
 if not cleanup['ok']:
  print('cleanup WARNING after %d attempt(s): %s' % (cleanup['attempts'],cleanup['error']),file=sys.stderr,flush=True)
 return runner_exit_code(rows,cleanup)
if __name__=='__main__':raise SystemExit(main())
