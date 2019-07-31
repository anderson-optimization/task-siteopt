
TEST_FILE=$1
LOGLEVEL=${3-DEBUG} 
SR_ID=$2
IMAGE="andersonopt/siteopt"

mkdir -p tmp/work/s_run/${SR_ID}
WORK_VOL=$(pwd)/tmp/work
cp -r src/* ${WORK_VOL}
cp -r test/ex-1/${SR_ID} tmp/work/s_run/
cp -r test/ex-1/dataItem tmp/work/

cat ${TEST_FILE} | \
	docker run -i --rm \
	-v ${WORK_VOL}:/work -w "/work" \
	-e "team=demo-alpha" \
	-e "user=google-oauth2|104792385606727687265" \
	-e "scenarioRun=${SR_ID}" \
	-e "loglevel=${LOGLEVEL}" \
	${IMAGE} \
	python3 task-siteopt.py 

