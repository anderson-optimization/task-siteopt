FROM ubuntu:latest

# Update
RUN apt-get update --fix-missing && apt-get upgrade -y

RUN apt-get install -y python3 python3-dev
RUN apt-get install -y python3-pip

RUN pip3 install --upgrade pip


WORKDIR /var/task

COPY build/requirements.txt /var/task/requirements.txt

ENV PYTHONPATH /var/task/.pypath

RUN \
  mkdir -p .pypath && \
  pip3 install cython -t .pypath/ 

RUN \
  pip3 install -r requirements.txt -t .pypath/ 

COPY build/requirements-custom.txt /var/task/requirements-custom.txt

RUN \
  pip3 install --upgrade -r requirements-custom.txt -t .pypath/ 

ADD lib/ao/ao /var/task/.pypath/ao
ADD lib/gams-parser/gams_parser /var/task/.pypath/gams_parser

ADD src /var/task/
