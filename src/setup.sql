
use role useradmin;
create role route_planner;
grant role route_planner to user {user};

use role sysadmin;
create database traveling_santa;
create schema traveling_santa.routes;

use role securityadmin;
grant all on database traveling_santa to role route_planner;
grant all on all schemas in database traveling_santa to role route_planner;
grant usage on warehouse compute_wh to role route_planner

use role route_planner;