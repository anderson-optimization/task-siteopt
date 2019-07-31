
TEST_FILE=$1
LOGLEVEL=${2-DEBUG} 
IMAGE="andersonopt/siteopt"

mkdir -p tmp/work
WORK_VOL=$(pwd)/tmp/work
cp src/* ${WORK_VOL}

cat ${TEST_FILE} | \
	docker run -i --rm \
	-v ${WORK_VOL}:/work -w "/work" \
	-v /media/eric/Workspace/dem:/data/dem \
	-e "team=demo-alpha" \
	-e "user=google-oauth2|104792385606727687265" \
	-e "loglevel=${LOGLEVEL}" \
	${IMAGE} \
	python3 task-siteopt.py 

