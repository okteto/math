from django.urls import include, re_path
from rest_framework import routers

from myproject import views


router = routers.DefaultRouter()
router.register(r'jobs', views.JobViewSet)

# Wire up our API using automatic URL routing.
# Additionally, we include login URLs for the browsable API.
urlpatterns = [
    re_path(r'^', include(router.urls)),
    re_path(r'^api-auth/', include('rest_framework.urls', namespace='rest_framework'))
]