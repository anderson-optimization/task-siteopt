
* Data sets , probably a csv
table demand(time,site)
$offlisting
**ao json2data group=demand "t{_index}	{row.AvgHourlyLoad(kW)}"
$onlisting
;
