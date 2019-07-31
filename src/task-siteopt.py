
import logging
import os
import sys

from ao.task import TaskHandle


logger = logging.getLogger('task')

task_handle=TaskHandle(stdin=sys.stdin,args=sys.argv,env=os.environ)

event = task_handle.event
team = task_handle.team
user = task_handle.user

if not event:
	task_handle.send_error(code='NO_EVENT',message="No event found.")
	sys.exit(1)
else:
	logger.debug("Have event")

#####################
### Set up Input ####
#####################




logger.debug("Analysis finished, send output!")
task_handle.send()