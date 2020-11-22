FROM ubuntu:latest

ENV TASKPATH /var/task
WORKDIR $TASKPATH

# Update
RUN apt-get update --fix-missing && apt-get upgrade -y

RUN apt-get install -y python3 python3-dev
RUN apt-get install -y python3-pip

RUN pip3 install --upgrade pip

# Copy dependencies
COPY gams.exe /tmp/gams.exe

# Install GAMS
ENV GAMSFOLDER gams24.9_linux_x64_64_sfx
ENV GAMSPATH ${TASKPATH}/${GAMSFOLDER}

RUN chmod +x /tmp/gams.exe && /tmp/gams.exe && rm /tmp/gams.exe
RUN ln -s $GAMSPATH gams

# Setup python bindings
RUN apt-get update && apt-get install -y python-dev

WORKDIR ${GAMSPATH}/apifiles/Python/api_36

RUN python3 setup.py install
ENV LD_LIBRARY_PATH ${GAMSPATH}

WORKDIR $TASKPATH


#Install gdxpds
# Encoding error on install https://github.com/attilaolah/diffbot.py/issues/13
ENV LC_CTYPE C.UTF-8
RUN pip3 install gdxpds -t .pypath
RUN pip3 install gdxpds

#COPY src/gdx_to_csv.py /bin/gdx_to_csv.py
#COPY src/format.json $TASKPATH/format.json

#RUN chmod +x /bin/gdx_to_csv.py

COPY build/requirements.txt requirements.txt
COPY build/requirements-custom.txt requirements-custom.txt

RUN pip3 install cython -t .pypath/ 
RUN \
  pip3 install -r requirements.txt -t .pypath/ 

COPY build/requirements-custom.txt /var/task/requirements-custom.txt

RUN \
  pip3 install --upgrade -r requirements-custom.txt -t .pypath/ 


RUN  pip3 install --force-reinstall awscli

ADD lib/ao/ao /var/task/.pypath/ao
ADD lib/gams-parser/gams_parser /var/task/.pypath/gams_parser

ADD src /var/task/
COPY src/gdx_to_csv.py /usr/bin/gdx_to_csv.py
RUN chmod +x /usr/bin/gdx_to_csv.py

ENV PYTHONPATH /var/task/.pypath

COPY cred/gamslice.txt	${GAMSPATH}/gamslice.txt
#RUN ln -s ${GAMSPATH}/gams /usr/bin/gams


RUN  pip3 install matplotlib seaborn