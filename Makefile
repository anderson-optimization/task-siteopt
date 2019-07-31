
IMAGE="andersonopt/siteopt"

all:
	echo "${IMAGE}"

test:
	bash scripts/run-test-stdin.sh test/ex-1/-LkzKKIRo8h6dhe_OueV/run.json -LkzKKIRo8h6dhe_OueV DEBUG


gams.exe: 
	curl -o gams.exe https://d37drm4t2jghv5.cloudfront.net/distributions/27.1.0/linux/linux_x64_64_sfx.exe

build: gams.exe
	docker build -t ${IMAGE} .

deploy:
	echo "Deploy to AWS"
##	docker push ${IMAGE}

inspect:
	docker run -it --rm \
		-v /media/eric/Workspace/dem:/data/dem \
		${IMAGE} /bin/bash

.PHONY: build test