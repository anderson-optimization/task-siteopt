parameter product_rate(supply,product,period,tier) /
**ao tariff product_rate
/;
parameter product_adj(supply,product,period,tier) /
**ao tariff product_adj
/;

set weekend_schedule(supply,product,month,hour,period) /
$offlisting
**ao tariff weekend_schedule
$onlisting
/;

set weekday_schedule(supply,product,month,hour,period) /
$offlisting
**ao tariff weekday_schedule
$onlisting
/;