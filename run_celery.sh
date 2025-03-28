#!/bin/sh

# wait for PSQL server to start
while ! curl --max-time 30 http://db:5432/ 2>&1 | grep '52'
do
    echo "Waiting for database..."
    sleep 1
done

if [ "$WAIT_FOR_FILE_SYNC" = "true" ]; then
while [ ! -f .syncthing-completed ]
do
    echo "Waiting for syncthing to complete..."
    sleep 1
done
fi

echo "SYNCTHING_COMPLETED_TIME: $(cat .syncthing-completed)"

cd myproject || exit 1

# run Celery worker for our project myproject with Celery configuration stored in Celeryconf
celery -A myproject worker -l INFO -Q default -n default@%h
