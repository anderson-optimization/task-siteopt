import pandas as pd
import itertools
import sys
import json
import os

from powopt import TouRate,create_time_map,run_pcm,get_path
from powopt import Output, DataOutput, FileOutput
print "Running AO Pypsa"

#scenarioRun=os.environ['scenarioRun']
if 'scenarioRun' in os.environ:
    scenario_run=os.environ['scenarioRun']
else:
    scenario_run="-LLHyhX9As1TDCOv4cGF"
print "Scenario run:",scenario_run

output_team="rmi-test-beta-system"

scenario_run_item=json.loads(sys.argv[2])
run_id=scenario_run_item['name']['runId']
print "scenario run item",run_id,scenario_run_item

load_file=None
tou_file=None
if scenario_run:
    scenario_folder='/'.join(['s_run',scenario_run])
    context_file='/'.join([scenario_folder,'context.json'])
    with open(context_file) as infile:
        data = json.load(infile)
        try:
            p_nom=float(get_path(data,'project.step.battery.parameter.batterysize.power'))
            duration=float(get_path(data,'project.step.battery.parameter.batterysize.duration'))
            charge_eff=float(get_path(data,'project.step.battery.parameter.batterycharacter.chargeEfficiency'))
            discharge_eff=float(get_path(data,'project.step.battery.parameter.batterycharacter.dischargeEfficiency'))
            data_files=get_path(scenario_run_item,'resource.data')
            print 'DataFiles: ',data_files
            load_files=[itemRef['rn'] for itemRef in data['data'] if itemRef['groupKey']=='demand']
            tou_files=[itemRef['rn'] for itemRef in data['data'] if itemRef['groupKey']=='tourate']
            print 'Load Files:',load_files
            print 'TOU Files:',tou_files
            f_load_id = load_files[0].split('/')[-1]
            f_tou_id = tou_files[0].split('/')[-1]
            load_file='dataItem/{file}.json'.format(file=f_load_id)
            tou_file='dataItem/{file}.json'.format(file=f_tou_id)
    
        except Exception as e:
            print "ERROR Loading scenario values for battery size"
            print "Error:",e
            p_nom=5
            duration=1
            #load_file='sierrita_load.json'
            #tou_file='sierrita_tou.json'
else:
    p_nom=5
    duration=1
###  Load and Time Map ######


print "demand file",load_file
data = pd.read_json(load_file)
dt_index=data['DateTime']
df_time=create_time_map(dt_index)
print data.columns
try:
    df_time['Load']=data['AvgHourlyLoad(kW)']
except:
    df_time['Load']=data['AverageLoad(kW)']
data=df_time
data['load']=data['Load']/1000



#### Tou Rates
print "Load TOU Rates",tou_file
with open(tou_file) as infile:
	tourate = json.load(infile)

tou = TouRate()
tou.load_open_ei_data(tourate)

def get_period(row):
	if row['dt_WEEKDAY']:
		return tou.demand.get_weekday_period(row['dt_M']-1,row['dt_H'])
	else:
		return tou.demand.get_weekend_period(row['dt_M']-1,row['dt_H'])


def get_rate(row):
	if row['dt_WEEKDAY']:
		return tou.energy.get_weekday_rate(row['dt_M']-1,row['dt_H'])*1000
	else:
		return tou.energy.get_weekend_rate(row['dt_M']-1,row['dt_H'])*1000

data['total_rate']=data.apply(get_rate,axis=1)
data['demand_period']=data.apply(get_period,axis=1)



## Buy / Sell

gens = [
	{
		"name":"buy",
		"p_nom":1000,
		"marginal_costs":data['total_rate']
	}
]

### Solar Gen


def prep_solar_data(data,solar_file):
	solar=pd.read_json(solar_file)
	min_solar=-solar.min()['gen']
	data['solar_load']=min_solar/1000
	solar_gen=(solar['gen']+min_solar)
	solar_p_nom_kw=solar_gen.max()
	data['solar_gen']=solar_gen/solar_p_nom_kw
	kwh_kw= solar.sum()/solar_p_nom_kw
	return solar_p_nom_kw/1000

#	print 'Solar Yield (kwh/kw):',kwh_kw

#data=data.head(240)

info={}
	
## Solar

## Inputs

#solar_p_nom_kw=size*1000
#solar_file="data/{}_{}.json".format(track,size)
solar_file="s_run/{sr}/nrel-sam-gen-{rid}.json".format(sr=scenario_run,rid=run_id)

#info['solar_tracking']=track
#info['solar_size']=size
info['solar_file']=solar_file

solar_p_nom=prep_solar_data(data,solar_file)
solar= [{
	"name": "solar",
	"p_nom": solar_p_nom,
	"p_max_pu": data['solar_gen'],
	"marginal_costs": 0
}]

## Battery


storage=[{
	"name":"storage",
	"p_nom":p_nom,
	"max_hours":duration,
	"efficiency_store":charge_eff,
	"efficiency_dispatch":discharge_eff
}]

info['battery_nom']=p_nom
info['battery_duration']=duration

results=run_pcm(data,tou,gens,solar,storage)

monthly= results.get('month')
hourly=results.get('hour')
month_period=results.get('month_period')

print('Hourly Keys',hourly.columns)

energy_nom=p_nom*duration
if energy_nom==0:
    energy_nom=1
hourly['movement']=hourly['dispatch'].abs()/energy_nom
hourly['cycles']=hourly['movement'].cumsum()/2
    
monthly['solar']=hourly.groupby('month').sum()['solar']
monthly['load']=hourly.groupby('month').sum()['load']
monthly['cycles']=hourly.groupby('month').sum()['movement']/2
monthly['buy']=hourly.groupby('month').sum()['buy']
monthly['buy_cost']=hourly.groupby('month').sum()['buy_cost']
monthly['avg_buy_cost']=monthly['buy_cost']/monthly['buy']


monthly.to_csv('maxgen.csv')
hourly.to_csv('out_data.csv')
month_period.to_csv('month_cost.csv')



month_file_path="s_run/{sr}/pcm-monthly-{rid}.csv".format(sr=scenario_run,rid=run_id)
hour_file_path="s_run/{sr}/pcm-hourly-{rid}.csv".format(sr=scenario_run,rid=run_id)
month_period_file_path="s_run/{sr}/pcm-monthperiod-{rid}.csv".format(sr=scenario_run,rid=run_id)

monthly.to_csv(month_file_path)
hourly.to_csv(hour_file_path)
month_period.to_csv(month_period_file_path)

month_file=FileOutput(
		name="PCM monthly [{rid}].csv".format(rid=run_id),
		item_id="pcm-monthly-{rid}-csv".format(rid=run_id),
		file_path=month_file_path,
		tid=output_team
	)
hour_file=FileOutput(
		name="PCM hourly [{rid}].csv".format(rid=run_id),
		item_id="pcm-hourly-{rid}-csv".format(rid=run_id),
		file_path=hour_file_path,
		tid=output_team
	)
monthperiod_file=FileOutput(
		name="PCM month-period [{rid}].csv".format(rid=run_id),
		item_id="pcm-monthperiod-{rid}-csv".format(rid=run_id),
		file_path=month_period_file_path,
		tid=output_team
	)
	
month_file.set_meta_data()
hour_file.set_meta_data()
monthperiod_file.set_meta_data()

hour_data_item={
    "body":{
        "file": "team/{tid}/file/{fid}".format(tid=output_team,fid='ao_'+hour_file.item_id)
    },
    "columns": [
        {
          "name": "Time Index",
          "prop": "",
          "visible": "legendonly"
        },
        {
          "name": "State of Charge",
          "prop": "state_of_charge"
        },
        {
          "name": "Battery Dispatch",
          "prop": "dispatch"
        },
        {
          "name": "Solar Gen",
          "prop": "solar"
        },
        {
          "name": "Load",
          "prop": "load"
        },
        {
          "name": "Buy",
          "prop": "buy"
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
        },
        {
          "name": "Movement",
          "prop": "movement"
        },
        {
          "name": "Cycles",
          "prop": "cycles",
          "visible": "legendonly"
        }
   ],
  "parameter": {
    "name": {
      "name": "Hourly [{rid}]".format(rid=run_id),
    }
  },
  "tags": [
    "timeseries",
    "data"
  ],
  "type": "data:timeseries"
}

month_data_item={
  "body": {
        "file": "team/{tid}/file/{fid}".format(tid=output_team,fid='ao_'+month_file.item_id)
  },
  "columns": [
    {
      "name": "month",
      "prop": "month",
      "timeIndex": True
    },
    {
      "name": "Energy Cost",
      "prop": "energy"
    },
    {
      "name": "Demand Charge",
      "prop": "demand"
    },
    {
      "name": "Total Cost",
      "prop": "total"
    },
    {
      "name": "Solar Gen",
      "prop": "solar"
    },
    {
      "name": "Load",
      "prop": "load"
    },
    {
      "name": "Buy",
      "prop": "buy"
    },
    {
      "name": "Mean Energy Cost",
      "prop": "avg_buy_cost"
    },
    {
      "name": "Cycles",
      "prop": "cycles"
    },
  ],
  "parameter": {
    "name": {
      "name": "Monthly [{rid}]".format(rid=run_id),
      "type": "parameter:name:basic"
    }
  },
  "tags": [
    "timeseries",
    "data"
  ],
  "type": "data:timeseries"
}

annual=monthly.sum()
print annual

task_output=Output()
task_output.set_data({
	"annual_electricity_cost":annual['total'],
	"annual_demand_charge":annual['demand'],
	"annual_energy_charge":annual['energy'],
	"annual_cycles":hourly['movement'].sum()/2,
	"battery_power":p_nom,
	"battery_duration": duration,
	"battery_energy": p_nom*duration
})
task_output.add_file(month_file.get_file_ref())
task_output.add_file(hour_file.get_file_ref())
task_output.add_file(monthperiod_file.get_file_ref())
task_output.add_data_item({
    "item":hour_data_item,
    "tid":output_team
    })
task_output.add_data_item({
    "item":month_data_item,
    "tid":output_team
    })
obj=task_output.get_output_obj()
print obj

