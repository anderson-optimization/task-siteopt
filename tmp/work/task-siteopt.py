
import logging
import os
import sys
import json

from ao.task import TaskHandle
from ao import get_path

from gams_parser import GamsParser
from util import write_datetime

logger = logging.getLogger('task')

os.environ['OUT_TEAM']="rmi-test-beta-system"

task_handle=TaskHandle(stdin=sys.stdin,args=sys.argv,env=os.environ)

event = task_handle.event
team = task_handle.team
user = task_handle.user

out_team = task_handle.out_team
scenario_id=task_handle.scenario_id

scenario_run = event
scenario_rid = event['name']['runId']

if not scenario_id or not scenario_run:
	task_handle.send_error(code='NO_SCENARIO',message="No scenario found.")
	sys.exit(1)
else:
	logger.debug("Have event")

#####################
### Set up Input ####
#####################


sc = task_handle.scenario_context
try:
	# Grab important parameters	
	p_nom=float(get_path(sc,'project.step.battery.parameter.batterysize.power'))
	duration=float(get_path(sc,'project.step.battery.parameter.batterysize.duration'))
	charge_eff=float(get_path(sc,'project.step.battery.parameter.batterycharacter.chargeEfficiency'))
	discharge_eff=float(get_path(sc,'project.step.battery.parameter.batterycharacter.dischargeEfficiency'))

	# Load files
	data_files=get_path(scenario_run,'resource.data')
	logger.debug('Found DataFiles: {} '.format(data_files))
	load_files=[itemRef['rn'] for itemRef in sc['data'] if itemRef['groupKey']=='demand']
	tou_files=[itemRef['rn'] for itemRef in sc['data'] if itemRef['groupKey']=='tourate']
	f_load_id = load_files[0].split('/')[-1]
	f_tou_id = tou_files[0].split('/')[-1]
	load_file='dataItem/{file}.json'.format(file=f_load_id)
	tou_file='dataItem/{file}.json'.format(file=f_tou_id)
	solar_file="{sf}/nrel-sam-gen-{rid}.json".format(sf=task_handle.scenario_folder,rid=scenario_rid)
	logger.debug('Load File: {}'.format(load_file))
	logger.debug('TOU File: {}'.format(tou_file))
	logger.debug('Solar file: {}'.format(solar_file))

	with open(load_file,'r') as in_file:
		load_data=json.load(in_file)

	with open(tou_file,'r') as in_file:
		tou_data=json.load(in_file)

	with open(solar_file,'r') as in_file:
		solar_data=json.load(in_file)

	logger.debug('Data loaded from files')

except Exception as e:
	logger.error('Error loading parameters for analysis',e)
	task_handle.send_error(code="ERROR_PARSING_PARAMETERS",message="Exception when parsing parameters for analysis")
	sys.exit(1)

############################
### Inject project data ####
############################

model_dir='{sf}/model'.format(sf=task_handle.scenario_folder)

try:
	os.makedirs(model_dir)
	os.makedirs('{dir}/time'.format(dir=model_dir))
except FileExistsError:
	pass

gp = GamsParser('./template/siteanalysis.gms')

d_map={
	"nrel-sam-gen": solar_data,
	f_tou_id: tou_data,
	f_load_id: load_data
}
new_model,inject_map=gp.inject(context=task_handle.scenario_context,data=d_map)

inject_map_file='{dir}/inject_map.json'.format(dir=model_dir)
with open(inject_map_file,'w') as out_file:
	json.dump(inject_map,out_file,indent=2)

model_file='{dir}/siteanalysis.gms'.format(dir=model_dir)
with open(model_file,'w') as out_file:
	out_file.write(new_model)

gp_gen = GamsParser('./template/gen.gms')
gen_model,im=gp_gen.inject(context=task_handle.scenario_context,data=d_map)
gen_file='{dir}/gen.gms'.format(dir=model_dir)
with open(gen_file,'w') as out_file:
	out_file.write(gen_model)

gp_demand = GamsParser('./template/demand.gms')
demand_model,im=gp_demand.inject(context=task_handle.scenario_context,data=d_map)
demand_file='{dir}/demand.gms'.format(dir=model_dir)
with open(demand_file,'w') as out_file:
	out_file.write(demand_model)

gp_tou = GamsParser('./template/tou.gms')
tou_model,im=gp_tou.inject(context=task_handle.scenario_context,data=d_map)
tou_file='{dir}/tou.gms'.format(dir=model_dir)
with open(tou_file,'w') as out_file:
	out_file.write(tou_model)

project_name=None
project_id=task_handle.scenario_context['project']['id']
for i in inject_map:
	if i['item_id']==project_id:
		project_name=i['item_name']

if not project_name:
	logger.error('Error finding project name')
	task_handle.send_error(code="NO_PROJECT_NAME",message="Could not find project name in injection map")
	sys.exit(1)

write_datetime(year=2018,folder=model_dir)


logger.debug('Run gams for project {}'.format(project_name))
task_handle.run(['gams',model_file,'--project',project_name])


logger.debug("Analysis finished, send output!")
task_handle.send()