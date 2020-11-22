
import logging
import os
import sys
import json

import zipfile
from os.path import basename

from ao.task import TaskHandle, FileOutput, ResourceOutput
from ao.gams import write_datetime
from ao import get_path

from gams_parser import GamsParser

import pandas as pd

logger = logging.getLogger('task')

out_team="rmi-test-beta-system"
os.environ['out_team']=out_team

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
output_dir='{sf}/output'.format(sf=task_handle.scenario_folder)
try:
	os.makedirs(model_dir)
	os.makedirs('{dir}/time'.format(dir=model_dir))
	os.makedirs(output_dir)
except FileExistsError:
	pass

gp = GamsParser('/var/task/template/siteanalysis.gms')

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

gp_gen = GamsParser('/var/task/template/gen.gms')
gen_model,im=gp_gen.inject(context=task_handle.scenario_context,data=d_map)
gen_file='{dir}/gen.gms'.format(dir=model_dir)
with open(gen_file,'w') as out_file:
	out_file.write(gen_model)

gp_demand = GamsParser('/var/task/template/demand.gms')
demand_model,im=gp_demand.inject(context=task_handle.scenario_context,data=d_map)
demand_file='{dir}/demand.gms'.format(dir=model_dir)
with open(demand_file,'w') as out_file:
	out_file.write(demand_model)

gp_tou = GamsParser('/var/task/template/tou.gms')
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
task_handle.run(['/var/task/gams/gams','siteanalysis.gms','--project',project_name],cwd=model_dir)

# from gdx_to_csv import convert_gdx_to_csv
# logger.debug('Gams run complete, convert output')
# convert_gdx_to_csv('model/output.gdx','output',gams_dir='/var/task/gams',wide=True,frmt='format.json')

task_handle.run(['python3','/usr/bin/gdx_to_csv.py',
		'-i','model/output.gdx',
		'-o','output',
		'-g','/var/task/gams',
		'-w',
		'-f','/var/task/format.json'],cwd=task_handle.scenario_folder)

output_results={}

solve_info='{sf}/output/model_info.csv'.format(sf=task_handle.scenario_folder)
with open(solve_info,'r') as in_file:
	solve_data=in_file.readlines()
	keyvalues = [line.strip().split(',') for line in solve_data]
	for kv in keyvalues:
		output_results['solve_{}'.format(kv[0])]=kv[1]

model_zip_file="{sf}/output/model.zip".format(sf=task_handle.scenario_folder)
zip_model = zipfile.ZipFile(model_zip_file, "w", zipfile.ZIP_DEFLATED)
zip_model.write(model_file,basename(model_file))
zip_model.write(gen_file,basename(gen_file))
zip_model.write(demand_file,basename(demand_file))
zip_model.write(tou_file,basename(tou_file))
zip_model.write(inject_map_file,basename(inject_map_file))
zip_model.close()

project_info_filename='{sf}/output/project_info.csv'.format(sf=task_handle.scenario_folder)
monthly_filename='{sf}/output/month_info.csv'.format(sf=task_handle.scenario_folder)

output_month_file=FileOutput(
		item_name="Month Summary {name}.scv".format(name=scenario_rid),
		item_type="file:data:csv",
		item_id="{name}-month-summary".format(name=scenario_rid),
		file_path=monthly_filename,
		tid=out_team
	)
output_month_period_file=FileOutput(
		item_name="Month-Period Summary {name}.csv".format(name=scenario_rid),
		item_type="file:data:csv",
		item_id="{name}-month-period-summary".format(name=scenario_rid),
		file_path='{sf}/output/month_period_info.csv'.format(sf=task_handle.scenario_folder),
		tid=out_team
	)
output_hourly_file=FileOutput(
		item_name="Hourly {name}.csv".format(name=scenario_rid),
		item_type="file:data:csv",
		item_id="{name}-hourly".format(name=scenario_rid),
		file_path=project_info_filename,
		tid=out_team
	)
output_model_file=FileOutput(
		item_name="Model {name}.zip".format(name=scenario_rid),
		item_type="file:archive",
		item_id="{name}-model-input".format(name=scenario_rid),
		file_path=model_zip_file,
		tid=out_team
	)


task_handle.add_resource(output_month_file)
task_handle.add_resource(output_month_period_file)
task_handle.add_resource(output_hourly_file)
task_handle.add_resource(output_model_file)



data_hourly_item={
    "body":{
        "file": output_hourly_file.get_rn_ref()['rn']
    },
    "columns": [
        {
          "name": "Time Index",
          "prop": "",
          "visible": "legendonly"
        },
        {
          "name": "Battery Energy",
          "prop": "batt_energy"
        },
        {
          "name": "Battery Dispatch",
          "prop": "batt_dispatch"
        },
        {
          "name": "Battery Store",
          "prop": "batt_store"
        },
        {
          "name": "Solar Gen",
          "prop": "solar"
        },
        {
          "name": "Solar Resource",
          "prop": "solar_resource",
          "visible": "legendonly"
        },
        {
          "name": "Load",
          "prop": "demand"
        },
        {
          "name": "Buy",
          "prop": "supply_buy"
        },
        {
          "name": "Buy Cost",
          "prop": "buy_cost",
          "visible": "legendonly"
        },
        {
          "name": "Demand Period",
          "prop": "demand_period"
        },
        {
          "name": "Energy Rate",
          "prop": "energy_rate"
        },
        {
          "name": "Date",
          "prop": "date",
          "timeIndex": True,
          "visible": "legendonly"
        },
        {
          "name": "Month",
          "prop": "month",
          "visible": "legendonly"
        },
        {
          "name": "Hour",
          "prop": "hour",
          "visible": "legendonly"
        },
        {
          "name": "Weekday",
          "prop": "weekday"
        }
   ],
  "parameter": {
    "name": {
      "name": "Hourly [{rid}]".format(rid=scenario_rid),
    }
  },
  "tags": [
    "timeseries",
    "data"
  ],
  "type": "data:timeseries"
}

hourly_output=ResourceOutput(item=data_hourly_item,resource='data',tid=out_team)
task_handle.add_resource(hourly_output)

month_data_item={
  "body": {
        "file": output_month_file.get_rn_ref()['rn']
  },
  "columns": [
    {
      "name": "month",
      "prop": "month",
      "timeIndex": True
    },
    {
      "name": "Energy Cost",
      "prop": "energy_cost"
    },
    {
      "name": "Demand Charge",
      "prop": "demand_cost"
    },
    {
      "name": "Total Cost",
      "prop": "total_cost"
    },
    {
      "name": "Solar Gen",
      "prop": "solar"
    },
    {
      "name": "Solar Resource",
      "prop": "solar_resource"
    },
    {
      "name": "Load",
      "prop": "demand"
    },
    {
      "name": "Buy",
      "prop": "supply_buy"
    },
    {
      "name": "Max Buy",
      "prop": "max_buy"
    },
    {
      "name": "Max Demand",
      "prop": "max_demand"
    },
    {
      "name": "Cycles",
      "prop": "batt_cycles"
    },
  ],
  "parameter": {
    "name": {
      "name": "Monthly [{rid}]".format(rid=scenario_rid),
      "type": "parameter:name:basic"
    }
  },
  "tags": [
    "timeseries",
    "data"
  ],
  "type": "data:timeseries"
}

month_output=ResourceOutput(item=month_data_item,resource='data',tid=out_team)
task_handle.add_resource(month_output)

df_hourly=pd.read_csv(project_info_filename)
df_monthly=pd.read_csv(monthly_filename)

output_results['annual_electricity_cost']=df_monthly['total_cost'].sum()
output_results['annual_energy_charge']=df_monthly['energy_cost'].sum()
output_results['annual_demand_charge']=df_monthly['demand_cost'].sum()

output_results['battery_cycles']=float(df_monthly['batt_cycles'].sum())
output_results['battery_power']=p_nom
output_results['battery_duration']=duration
output_results['battery_energy']=p_nom*duration

task_handle.set_data(output_results)

logger.debug("Analysis finished, send output!")
task_handle.send()