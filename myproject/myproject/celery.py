import os

from celery import Celery
from django.conf import settings

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "myproject.settings")

app = Celery('myproject')

CELERY_TIMEZONE = 'UTC'

app.config_from_object('django.conf:settings')
app.autodiscover_tasks()