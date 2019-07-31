
IMAGE="andersonopt/siteopt"

all:
	echo "${IMAGE}"

test:
	bash scripts/run-test-stdin.sh test/ex-1.json DEBUG



build:
	docker build -t ${IMAGE} .

deploy:
	docker push ${IMAGE}

inspect:
	docker run -it --rm \
		-v /media/eric/Workspace/dem:/data/dem \
		${IMAGE} /bin/bash

.PHONY: build test