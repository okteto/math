"""
Pytest configuration and fixtures for Django + Celery app tests
"""
import os
import time
import pytest
import requests
from typing import Dict, Any


# Base URL configuration
OKTETO_NAMESPACE = os.environ.get('OKTETO_NAMESPACE', 'agent-4dx94ofejmcy')
BASE_URL = f"http://web.{OKTETO_NAMESPACE}.svc.cluster.local:8080"


@pytest.fixture(scope="session", autouse=True)
def wait_for_services():
    """Wait for services to be ready before running tests"""
    print(f"\n{'='*50}")
    print("Waiting for services to be ready...")
    print(f"Base URL: {BASE_URL}")
    print(f"Namespace: {OKTETO_NAMESPACE}")
    print(f"{'='*50}\n")

    max_retries = 30
    retry_count = 0

    while retry_count < max_retries:
        try:
            response = requests.get(f"{BASE_URL}/", timeout=5)
            if response.status_code in [200, 404]:
                print(f"✓ Web service is ready! (HTTP {response.status_code})")
                break
        except requests.exceptions.RequestException as e:
            retry_count += 1
            if retry_count < max_retries:
                print(f"Attempt {retry_count}/{max_retries} - Web service not ready, waiting...")
                time.sleep(2)
            else:
                raise Exception(f"Web service did not become ready in time: {e}")

    # Additional stabilization time
    print("Waiting 5 seconds for all services to stabilize...")
    time.sleep(5)
    print("Services ready! Starting tests...\n")


@pytest.fixture(scope="session")
def api_client():
    """Returns the base URL for the API"""
    return BASE_URL


@pytest.fixture
def wait_for_job_completion():
    """Fixture that provides a function to wait for job completion"""
    def _wait_for_job(job_url: str, max_wait: int = 15, expected_status: str = "finished") -> Dict[str, Any]:
        """
        Wait for a job to reach expected status

        Args:
            job_url: Full URL to the job endpoint
            max_wait: Maximum seconds to wait
            expected_status: Expected job status

        Returns:
            Job data dictionary
        """
        wait_count = 0
        while wait_count < max_wait:
            response = requests.get(job_url)
            job_data = response.json()

            if job_data.get("status") == expected_status:
                return job_data

            wait_count += 1
            time.sleep(1)

        # Return final state even if not expected
        response = requests.get(job_url)
        return response.json()

    return _wait_for_job


@pytest.fixture
def create_job(api_client):
    """Fixture that provides a function to create jobs"""
    def _create_job(job_type: str, argument: int, status: str = "pending") -> Dict[str, Any]:
        """
        Create a new job

        Args:
            job_type: Type of job ("power" or "fibonacci")
            argument: Argument for the computation
            status: Initial status (default: "pending")

        Returns:
            Job data dictionary
        """
        response = requests.post(
            f"{api_client}/jobs/",
            json={
                "type": job_type,
                "status": status,
                "argument": argument
            },
            headers={"Content-Type": "application/json"}
        )
        response.raise_for_status()
        return response.json()

    return _create_job
