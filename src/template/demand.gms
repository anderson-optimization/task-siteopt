
* Data sets , probably a csv
table demand_t(time,demand)
$offlisting
**ao json2data group=demand "t{_index}	{row.AvgHourlyLoad(kW)}"
$onlisting
;
