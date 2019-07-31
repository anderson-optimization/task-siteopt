FROM osgeo/gdal:ubuntu-full-latest

# Update
RUN apt-get update && apt-get upgrade -y

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

ADD ao/ao /var/task/.pypath/ao

ADD src /var/task/
