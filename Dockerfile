FROM python:3.9

ENV PYTHONUNBUFFERED true 

# set working directory to /app/
WORKDIR /app/

# copy requirements.txt to the image
COPY requirements.txt requirements.txt

# install python dependencies
RUN pip install -r requirements.txt

# copy code base to the image
COPY . .

CMD ["./run_web.sh"]