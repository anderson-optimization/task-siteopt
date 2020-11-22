

$onempty

* Handle to long of numbers
$offdigit

* Ensure project is set
$if not set project $abort


*****************
*** Overrides ***
*****************
* Pre Init
**********


**********************
*** Initialization ***
**********************
* Primary AO Injection
**********************

** Time definition


set
    time                            "Time index of model (hourly)."     /t0*t8760/
    year                            "Years possible in the simulation"  /y2000*y2040/
    month                           "Months of the year"                /m1*m12/
    hour                            "Hour of the data"                  /h1*h24/
    day_of_week                     "Day of week"                       /dow1*dow7/

*   Map datetime to model time
    datetime_comp                   "Datetime components used to map a time index to a real datetime." 
                        /year,month,day,hour,minute,dayofweek,weekday,weekend,datetime/
    
*   Maps
    month2t(month,time)             "Map month to time"
    hour2t(hour,time)               "Map hour to time"
    weekend2t(time)                 "Map weekend to time"
    weekday2t(time)                 "Map weekday to time"

    month_time_first(month,time)    "First time of month"
    month_time_last(month,time)     "Last time of month"

    time_first(time)                "First time of analyis"
    time_last(time)                 "Last time of analysis"


*   Subsets of time to include in solve
    ch(time)                        "These time elements are included in the current solve."
    chm(month)                      "These months are included in the current solve."
;

alias (time,t);   

ch(time)=1;
chm(month)=1;

table datetime_map(time,datetime_comp) "Map relating model time to a specific date"                                                             
$ondelim offlisting
$include time/datetime_map_2018.csv
$offdelim onlisting
;

month2t(month,time)$(datetime_map(time,'month')=ord(month))=Yes;
hour2t(hour,time)$(datetime_map(time,'hour')+1=ord(hour))=Yes;
weekend2t(time)$(datetime_map(time,'weekend')=1)=Yes;
weekday2t(time)$(datetime_map(time,'weekday')=1)=Yes;

month_time_first(month,time)$(month2t(month,time) and ord(time)=smin(t$month2t(month,t),ord(t)))=YES;
month_time_last(month,time)$(month2t(month,time) and ord(time)=smax(t$month2t(month,t),ord(t)))=YES;

time_first(time)$(ord(time)=smin(t,ord(t)))=YES;
time_last(time)$(ord(time)=smax(t,ord(t)))=YES;


* Project
set project "Projects are grouping of assets, data, and parameters" /
**ao list project
/;

* Asset
set asset "Assets are physical objects used in analysis" /
**ao list asset
new_solar
new_battery
/;

set site(asset) "A site with a corresponding load" /
**ao list asset "type startswith asset:land"
/;

set gen(asset) "Generators attach to a single bus and can feed in power" /
**ao list asset "type startswith asset:gen"
**ao list asset "type startswith asset:battery"
new_solar
new_battery
/;

set control_gen(gen) "Operational generators can be controlled and used to respond to variations in demand" / 
**ao list asset "type startswith asset:gen:combined"
**ao list asset "type startswith asset:gen:combustion"
**ao list asset "type startswith asset:gen:hydro"
**ao list asset "type startswith asset:gen:steam"
/;

set renewable(gen) "Renewable generators are not controllable, have max gen according to a resource, and can be curtailed" / 
**ao list asset "type startswith asset:gen:renewable"
new_solar
/;

set solar(gen) "Solar generators have a max generation corresponding to a solar resource and can be curtailed" / 
**ao list asset "type startswith asset:gen:renewable:solar"
new_solar
/;

set wind(gen) "Wind generators have a max generation corresponding to a wind resource and can be curtailed" / 
**ao list asset "type startswith asset:gen:renewable:wind"
/;


set battery(gen)  "Batteries can be charged, discharged, and have a state of charge" / 
**ao list asset "type startswith asset:battery"
new_battery
/;

* Data
set data "AO Data objects" /
**ao list data
/;
set demand(data) "Project demand" /
**ao list data "groupKey == demand"
/;
set supply(data) "Electrical supply data, TOU Rates"/
**ao list data "groupKey == tourate"
/;


** Maps

set project2asset(project,asset) "Map associating projects with data" /
**ao map project asset
**ao map project 'new_battery'
**ao map project 'new_solar'
/;

set project2data(project,data) "Map associating projects with data" /
**ao map project data
/;

** Parameters

* Fields

set financial_field "Financial parameter fields" / 
    discountRate
    federalTaxRate
    stateTaxRate
    inflationRate
    omEscalationRate
    period
/;

set solar_field "Solar parameter fields" /
    capacityCost
    capacityPower
    degradationRate
    omCost
/;
set battery_field "Battery parameter fields" / 
    capacityCosts
    energyCosts
    power
    duration
    chargeEfficiency
    dischargeEfficiency
    cycleCost
/;

parameter param_financial(project,financial_field) "Parameters for project of financial step" /
**ao param project 'step.financial.parameter.simplefinance'
/;

parameter param_solar(project,solar_field) "Parameters for project of solar step" /
**ao param project 'step.solar.parameter.solar'
/;

** SOC min/max????
parameter param_battery(project,battery_field) "Parameters for project of battery step" /
**ao param project 'step.battery.parameter.batterycapitalcost'
**ao param project 'step.battery.parameter.batterycharacter'
**ao param project 'step.battery.parameter.batterysize'
/;


* Generator parameters
parameter   
            p_nom(gen)                  "Nominal power of generator (MW)"
            marginal_cost(gen)          "Marginal cost of generation ($/MWh)"

* Renewables
            p_max_pu_t(time,gen)        "Max generation per unit capacity by time [0,1]"

* Battery
            duration(gen)               "Duration of battery (t)"
            energy_capacity(gen)        "Energy capacity (MWh)"
            efficiency_store(gen)       "Efficiency of storing energy [0,1]"
            efficiency_dispatch(gen)    "Efficiency of dispatching energy [0,1]"
            soc_min(gen)                "State of charge min [0,1]"
            soc_max(gen)                "State of charge max [0,1]"
            cycle_cost(gen)             "Cost/cycle ($)"
;

* Data sets
parameter demand_t(time,demand) "hourly demand (MW)";
$include demand.gms

$include gen.gms

* Convert to MW
demand_t(time,demand)=demand_t(time,demand)/1000;
p_max_pu_t(time,gen)=p_max_pu_t(time,gen)/1000;


p_nom(gen)=0;

** Set parameters
p_nom('new_solar')      = param_solar('%project%','capacityPower');
p_nom('new_battery')    = param_battery('%project%','power');
duration('new_battery') = param_battery('%project%','duration');

energy_capacity(battery)    = p_nom(battery)*duration(battery);

marginal_cost('new_solar')      = 0;
marginal_cost('new_battery')    = 0;
cycle_cost('new_battery')       =  param_battery('%project%','cycleCost');

soc_min(battery) = .15;
soc_max(battery) = .95;

efficiency_dispatch('new_battery')  = param_battery('%project%','dischargeEfficiency');
efficiency_store('new_battery')     = param_battery('%project%','chargeEfficiency');


*** this is a data object that needs to be encoded by data id
** Supply/Schedule Implementation


set product     "Product for energy supply"                 
                    /energy,demand/
    period      "Periods define different rate structures"  
                    /period1*period10/
    tier        "Tiers are used to define different rates based on buy values"
                    /tier1*tier10/

*   Map
    supply_product_period2time(supply,product,period,time)  "Map matching individual times to product period"
    month2demand_period(month,period)                       "Month has period";

parameter product_rate(supply,product,period,tier)          "Rate of energy/demand cost ($/kWh and $/kW)"
            product_adj(supply,product,period,tier)         "Rate of adjustment ($/kWh and $/kW)";

set weekday_schedule(supply,product,month,hour,period)      "Supply schedule defining period for weekdays"
    weekend_schedule(supply,product,month,hour,period)      "Supply schedule defining period for weekends";




** Tariff definition
$include tou.gms

* Calculate TOU Values

supply_product_period2time(supply,product,period,t)= sum((month,hour)
    $(month2t(month,t) and hour2t(hour,t) 
        and weekend_schedule(supply,product,month,hour,period)),
        1
    )$weekend2t(t)

*   Weekday
    +sum((month,hour)$(month2t(month,t) and hour2t(hour,t)
            and weekday_schedule(supply,product,month,hour,period)),
        1
    )$weekday2t(t);


month2demand_period(month,period)=sum((supply,t)$month2t(month,t),supply_product_period2time(supply,'demand',period,t));

parameter energy_rate(supply,time)          "Energy rate for supply at time ($/MWh)"
          demand_rate(supply,month,period)  "Demand rate for supply during month period ($/MW)";

energy_rate(supply,time)=1000*sum(period$supply_product_period2time(supply,'energy',period,time),
                                product_rate(supply,'energy',period,'tier1')
*                               + product_adj(supply,'energy',period,'tier1')
                            );
demand_rate(supply,month,period)=1000*(product_rate(supply,'demand',period,'tier1')
*                                   +product_adj(supply,'demand',period,'tier1'));
                            );


*****************
*** Overrides ***
*****************
* Pre Model
***********


*************
*** Model ***
*************

Variables   
    totalC                                  "Total cost of supplying energy over time frame"

*   Project (Balancing level)
    projectCM(project,month)                "Cost of supplying project for month"
    projectX(project,time)                  "Net power of project (assume = 0)"

*   Supply - Cost
    supply_energyCM(supply,month)           "Cost of energy supply for month"
    supply_demandCM(supply,month)           "Cost of demand charges for month"
    supply_energyCT(supply,time)            "Cost of energy supply at time"
    supply_demandCMP(supply,month,period)   "Cost of max buy for supply during month-period"

*   Supply - Power
    supplyX(supply,time)                    "Net supply at time"
    buyX(supply,time)                       "Amount purchased from supply at time"
    sellX(supply,time)                      "Amount sold to supply at time"
    max_buyX(supply,month,period)           "Max buy for supply during month-period"

*   Generation
    genC(gen,time)                          "Cost of gen at time"
    genCM(gen,month)                        "Cost of gen during month"
    genX(gen,time)                          "Amount generated from gen at time"

*   Energy Storage  
    storeX(gen,time)                        "Amount stored by gen at time (storage unit)"
    dispatchX(gen,time)                     "Amount dispatched by gen at time (storage unit)"
    energyX(gen,time)                       "Amount of energy at time (storage unit)";

** Bounds
Positive variables genC,genCM,storeX,dispatchX,energyX;
Positive variables supply_energyCM,supply_demandCM,supply_energyCT,supply_demandCMP;
Positive variables buyX,sellX,max_buyX;

projectX.up(project,time)=0;
projectX.lo(project,time)=0;

genX.up(gen,time)=p_nom(gen);
genX.lo(gen,time)=0;
genX.lo(battery,time)=-p_nom(battery);

genX.up(renewable,time)=p_max_pu_t(time,renewable);
parameter p_min(gen);
p_min(renewable)=smin(t,p_max_pu_t(t,renewable));
genX.lo(renewable,time)=p_min(renewable);

sellX.up(supply,time)=0;

energyX.up(battery,time)=soc_max(battery)*energy_capacity(battery);
*energyX.lo(battery,time)=soc_min(battery)*energy_capacity(battery);

Equations
*   Objective
    total_cost                                  "total cost of system"

*   Cost components
    project_cost_month(project,month)           "project cost during month"
    energy_cost_month(supply,month)             "energy cost during month"
    energy_cost(supply,time)                    "energy cost at time"                   
    demand_cost_month(supply,month)             "demand charge during month"
    demand_cost(supply,month,period)            "demand charge during month-period"
    gen_cost_month(gen,month)                   "gen cost during month"
    gen_cost(gen,time)                          "gen cost at time"

*   Project Energy Balance
    project_balance(project,time)               "energy balance at project"

*   Supply Balance
    supply_operation(supply,time)               "Supply operation signed"
    supply_max_buy(supply,month,period,time)    "Max buy for supply during month-period"

*   Energy Storage
    storage_balance(battery,time)               "Storage inventory balance"
    battery_power(battery,time)                 "Max power of battery over all operation"
    battery_operation(battery,time)             "Battery operational signed"
    battery_boundary_condition(battery)         "Boundary condition for energy of battery"
;

*** Equation Definitions

total_cost..

    totalC =g=
        sum(month$chm(month),
            sum(project,
                projectCM(project,month)
            )
        );


project_cost_month(project,month)$chm(month)..

    projectCM(project,month) =g=
        sum(gen$project2asset(project,gen),
                genCM(gen,month)
            )
        +
        sum(supply$project2data(project,supply),
                supply_energyCM(supply,month)
                + supply_demandCM(supply,month)
            );


* A buy/sell spread probably should be here at some point
energy_cost_month(supply,month)$chm(month)..

    supply_energyCM(supply,month) =g=
    sum(time$month2t(month,time),
            supply_energyCT(supply,time)
        );

energy_cost(supply,time)..

    supply_energyCT(supply,time) =g=
            buyX(supply,time)*energy_rate(supply,time)
            - sellX(supply,time)*energy_rate(supply,time);

demand_cost_month(supply,month)$chm(month)..

    supply_demandCM(supply,month) =g=
    sum(period,
            supply_demandCMP(supply,month,period)
        );


demand_cost(supply,month,period)..

    supply_demandCMP(supply,month,period) =g=
        max_buyX(supply,month,period)*demand_rate(supply,month,period);

gen_cost_month(gen,month)$chm(month)..

    genCM(gen,month) =g= 
        sum(time$(ch(time) and month2t(month,time)),
                genC(gen,time)
            );


gen_cost(gen,time)$ch(time)..

    genC(gen,time) =g=
        marginal_cost(gen)*genX(gen,time)
        + (cycle_cost(gen)*(dispatchX(gen,time)+storeX(gen,time)))$battery(gen);



project_balance(project,time)$ch(time)..

    projectX(project,time) =e=
        sum(gen$project2asset(project,gen),
                genX(gen,time)
            )
        + 
        sum(supply$project2data(project,supply),
                supplyX(supply,time)
            )
        - sum(demand$project2data(project,demand),
                demand_t(time,demand)
            );


supply_operation(supply,time)$ch(time)..

    supplyX(supply,time) =e=
        buyX(supply,time)
        - sellX(supply,time);


supply_max_buy(supply,month,period,time)$(month2t(month,time) and supply_product_period2time(supply,'demand',period,time))..

    max_buyX(supply,month,period) =g=
        buyX(supply,time);
            

storage_balance(battery,time)$ch(time)..

    energyX(battery,time+1) =e=
        energyX(battery,time)
        + storeX(battery,time)*efficiency_store(battery)
        - dispatchX(battery,time);


battery_power(battery,time)$ch(time)..
    
    storeX(battery,time)
    + dispatchX(battery,time)
    =l= 
    p_nom(battery);


battery_operation(battery,time)$ch(time)..

    genX(battery,time)
    =e=
    dispatchX(battery,time)*efficiency_dispatch(battery)
    - storeX(battery,time);

battery_boundary_condition(battery)..

    sum(time_first,energyX(battery,time_first)) 
    =e=
    sum(time_last,energyX(battery,time_last));

*****************
*** Overrides ***
*****************
* Pre Solve
***********


*************
*** Solve ***
*************


model site_analysis /
    all
/;

solve site_analysis using lp minimizing totalC;



*****************
*** Overrides ***
*****************
* Post Solve
************


******************
*** Extraction ***
******************
* Data exfil
************


* Project Information
set project_info_fields "Project information fields" 
                            /year,month,day,hour,datetime,weekend,
                                demand,gen,supply,
                                batt_store,batt_dispatch,batt_energy,batt_movement,batt_cycles,
                                supply_buy,supply_sell,
                                solar,wind,solar_resource,wind_resource,
                                demand_period,energy_period,
                                marginal_price,buy_cost,energy_rate/
    month_info_fields   "Results on a monthly basis"
                            /year,month,
                                demand,gen,
                                batt_store,batt_dispatch,batt_cycles,
                                supply_buy,supply_sell,
                                max_buy,max_demand,
                                solar,solar_resource,wind,wind_resource
                                energy_cost,demand_cost,total_cost/
    month_period_info_fields    "Results on a monthl-period basis"
                            /year,month,period,
                                max_buy,max_demand,demand_cost,demand_rate/
    model_info_fields   "Optimization solve information fields" 
                            /modelstat,solvestat,objval,best,actual,gap,resusd/
;                   

parameter 
    project_info(t,project_info_fields) "Project operational details"
    month_info(month,month_info_fields) "Project monthly details"
    month_period_info(month,period,month_period_info_fields) "Project monthl-period details"
    model_info(model_info_fields)       "Optimization solve details"
;





*   Store project information
project_info(t,'year')      = datetime_map(t,'year');
project_info(t,'month')     = datetime_map(t,'month');
project_info(t,'day')       = datetime_map(t,'day');
project_info(t,'hour')      = datetime_map(t,'hour');
project_info(t,'datetime')  = datetime_map(t,'datetime');
project_info(t,'weekend')   = datetime_map(t,'weekend');

project_info(t,'demand')        = sum(demand,demand_t(t,demand));
project_info(t,'gen')           = sum(gen,genX.l(gen,t));
project_info(t,'supply')        = sum(supply, buyX.l(supply,t)-sellX.l(supply,t));
project_info(t,'solar')         = sum(solar,genX.l(solar,t));
project_info(t,'solar_resource')= sum(solar,p_max_pu_t(t,solar));
project_info(t,'wind')          = sum(wind,genX.l(wind,t));
project_info(t,'wind_resource') = sum(wind,p_max_pu_t(t,wind));
project_info(t,'batt_store')    = sum(battery,storeX.l(battery,t));
project_info(t,'batt_dispatch') = sum(battery,dispatchX.l(battery,t));
project_info(t,'batt_energy')   = sum(battery,energyX.l(battery,t));
project_info(t,'batt_movement') = sum(battery$energy_capacity(battery),(dispatchX.l(battery,t)+storeX.l(battery,t))/energy_capacity(battery));
project_info(t,'batt_cycles')   = sum(time$(ord(time)<=ord(t)),project_info(time,'batt_movement'))/2;
project_info(t,'supply_buy')    = sum(supply,buyX.l(supply,t));
project_info(t,'supply_sell')   = sum(supply,sellX.l(supply,t));

project_info(t,'demand_period') = smax((supply,period)$supply_product_period2time(supply,'demand',period,t),ord(period));
project_info(t,'energy_period') = smax((supply,period)$supply_product_period2time(supply,'energy',period,t),ord(period));

project_info(t,'marginal_price')    = project_balance.m('%project%',t); 
project_info(t,'energy_rate')       = smax(supply,energy_rate(supply,t));
project_info(t,'buy_cost')          = sum(supply,supply_energyCT.l(supply,t));


month_info(month,'year')    = sum(t$month_time_first(month,t),project_info(t,'year'));
month_info(month,'month')   = sum(t$month_time_first(month,t),project_info(t,'month'));

month_info(month,'demand')          = sum(t$month2t(month,t),project_info(t,'demand'));
month_info(month,'gen')             = sum(t$month2t(month,t),project_info(t,'gen'));
month_info(month,'solar')           = sum(t$month2t(month,t),project_info(t,'solar'));
month_info(month,'solar_resource')  = sum(t$month2t(month,t),project_info(t,'solar_resource'));
month_info(month,'wind')            = sum(t$month2t(month,t),project_info(t,'wind'));
month_info(month,'wind_resource')   = sum(t$month2t(month,t),project_info(t,'wind_resource'));
month_info(month,'batt_store')      = sum(t$month2t(month,t),project_info(t,'batt_store'));
month_info(month,'batt_dispatch')   = sum(t$month2t(month,t),project_info(t,'batt_dispatch'));
month_info(month,'batt_cycles')     = sum(t$month2t(month,t),project_info(t,'batt_movement'))/2;
month_info(month,'supply_buy')      = sum(t$month2t(month,t),project_info(t,'supply_buy'));
month_info(month,'supply_sell')     = sum(t$month2t(month,t),project_info(t,'supply_sell'));

month_info(month,'max_buy') = smax((supply,t)$month2t(month,t),buyX.l(supply,t));
month_info(month,'max_demand') = smax((demand,t)$month2t(month,t),demand_t(t,demand));

month_info(month,'energy_cost')   = sum(supply,supply_energyCM.l(supply,month));
month_info(month,'demand_cost')   = sum(supply,supply_demandCM.l(supply,month));
month_info(month,'total_cost')   = sum(supply,supply_energyCM.l(supply,month)+supply_demandCM.l(supply,month));

        
month_period_info(month,period,'year')$month2demand_period(month,period)    = sum(t$month_time_first(month,t),project_info(t,'year'));
month_period_info(month,period,'month')$month2demand_period(month,period)   = ord(month);
month_period_info(month,period,'period')$month2demand_period(month,period)  = ord(period);

month_period_info(month,period,'max_buy')$month2demand_period(month,period) = smax(supply,max_buyX.l(supply,month,period));
month_period_info(month,period,'max_demand')$month2demand_period(month,period) = smax((demand,supply,t)$(month2t(month,t) and supply_product_period2time(supply,'demand',period,t)),demand_t(t,demand));
month_period_info(month,period,'demand_cost')$month2demand_period(month,period) = sum(supply,supply_demandCMP.l(supply,month,period));
month_period_info(month,period,'demand_rate')$month2demand_period(month,period) = sum(supply,demand_rate(supply,month,period));

        

*   Store model info
model_info('modelstat') = site_analysis.modelstat;
model_info('solvestat') = site_analysis.solvestat;
model_info('objval')    = site_analysis.objval;
model_info('resusd')    = site_analysis.resusd;

execute_unload "output" project_info model_info month_period_info month_info;

display project_info;
display month_period_info;
display month_info;
display model_info;