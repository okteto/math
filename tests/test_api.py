"""
API endpoint tests for Django + Celery application
"""
import pytest
import requests


@pytest.mark.api
class TestAPIEndpoints:
    """Test API endpoint accessibility and responses"""

    def test_root_endpoint_accessible(self, api_client):
        """Test that the API root endpoint is accessible"""
        response = requests.get(f"{api_client}/")
        assert response.status_code == 200

    def test_jobs_list_endpoint(self, api_client):
        """Test that jobs list endpoint returns valid JSON"""
        response = requests.get(f"{api_client}/jobs/")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)

    def test_job_retrieval_by_id(self, api_client, create_job):
        """Test that individual jobs can be retrieved by ID"""
        # Create a job
        job = create_job("power", 5)
        job_url = job["url"]

        # Retrieve the job
        response = requests.get(job_url)
        assert response.status_code == 200

        retrieved_job = response.json()
        assert "url" in retrieved_job
        assert retrieved_job["type"] == "power"
        assert retrieved_job["argument"] == 5


@pytest.mark.jobs
class TestJobCreation:
    """Test job creation for different types"""

    def test_create_power_job(self, api_client, create_job):
        """Test creating a power job"""
        job = create_job("power", 10)

        assert job["type"] == "power"
        assert job["status"] == "pending"
        assert job["argument"] == 10
        assert job["result"] is None
        assert "url" in job

    def test_create_fibonacci_job(self, api_client, create_job):
        """Test creating a fibonacci job"""
        job = create_job("fibonacci", 15)

        assert job["type"] == "fibonacci"
        assert job["status"] == "pending"
        assert job["argument"] == 15
        assert job["result"] is None
        assert "url" in job


@pytest.mark.jobs
class TestJobProcessing:
    """Test job processing and completion"""

    def test_power_job_completes(self, create_job, wait_for_job_completion):
        """Test that power job completes successfully with correct result"""
        job = create_job("power", 10)
        job_url = job["url"]

        # Wait for job to complete
        completed_job = wait_for_job_completion(job_url, max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 1024  # 2^10 = 1024

    def test_fibonacci_job_completes(self, create_job, wait_for_job_completion):
        """Test that fibonacci job completes successfully with correct result"""
        job = create_job("fibonacci", 15)
        job_url = job["url"]

        # Wait for job to complete
        completed_job = wait_for_job_completion(job_url, max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 610  # fib(15) = 610

    def test_large_power_calculation(self, create_job, wait_for_job_completion):
        """Test large power calculation (2^20)"""
        job = create_job("power", 20)
        job_url = job["url"]

        # Wait for job to complete
        completed_job = wait_for_job_completion(job_url, max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 1048576  # 2^20 = 1048576


@pytest.mark.edge_cases
class TestEdgeCases:
    """Test edge cases for job processing"""

    def test_fibonacci_zero(self, create_job, wait_for_job_completion):
        """Test fibonacci edge case: fib(0) = 0"""
        job = create_job("fibonacci", 0)
        completed_job = wait_for_job_completion(job["url"], max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 0

    def test_fibonacci_one(self, create_job, wait_for_job_completion):
        """Test fibonacci edge case: fib(1) = 1"""
        job = create_job("fibonacci", 1)
        completed_job = wait_for_job_completion(job["url"], max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 1

    def test_power_zero(self, create_job, wait_for_job_completion):
        """Test power edge case: 2^0 = 1"""
        job = create_job("power", 0)
        completed_job = wait_for_job_completion(job["url"], max_wait=15)

        assert completed_job["status"] == "finished"
        assert completed_job["result"] == 1


@pytest.mark.validation
class TestInputValidation:
    """Test API input validation"""

    def test_invalid_job_type_rejected(self, api_client):
        """Test that API rejects invalid job types"""
        response = requests.post(
            f"{api_client}/jobs/",
            json={
                "type": "invalid",
                "status": "pending",
                "argument": 5
            },
            headers={"Content-Type": "application/json"}
        )

        # Should return 400 Bad Request
        assert response.status_code == 400
        error_data = response.json()
        assert "type" in error_data or "error" in str(error_data).lower()

    def test_incomplete_job_data_rejected(self, api_client):
        """Test that API rejects incomplete job data"""
        response = requests.post(
            f"{api_client}/jobs/",
            json={"type": "power"},
            headers={"Content-Type": "application/json"}
        )

        # Should return 400 Bad Request
        assert response.status_code == 400
        error_data = response.json()
        # Should indicate missing required fields
        assert "status" in error_data or "argument" in error_data


@pytest.mark.integration
class TestIntegration:
    """Integration tests for full workflow"""

    def test_all_jobs_appear_in_list(self, api_client, create_job):
        """Test that all created jobs appear in the job list"""
        # Get initial count
        response = requests.get(f"{api_client}/jobs/")
        initial_count = len(response.json())

        # Create test jobs
        create_job("power", 3)
        create_job("fibonacci", 5)

        # Check updated list
        response = requests.get(f"{api_client}/jobs/")
        assert response.status_code == 200

        jobs = response.json()
        assert len(jobs) >= initial_count + 2

    def test_concurrent_job_processing(self, api_client, create_job, wait_for_job_completion):
        """Test multiple concurrent jobs are processed successfully"""
        # Create multiple jobs quickly
        job1 = create_job("power", 5)
        job2 = create_job("fibonacci", 10)
        job3 = create_job("power", 7)

        # Wait for all to complete
        import time
        time.sleep(7)

        # Check all completed
        completed1 = wait_for_job_completion(job1["url"], max_wait=1)
        completed2 = wait_for_job_completion(job2["url"], max_wait=1)
        completed3 = wait_for_job_completion(job3["url"], max_wait=1)

        assert completed1["status"] == "finished"
        assert completed1["result"] == 32  # 2^5

        assert completed2["status"] == "finished"
        assert completed2["result"] == 55  # fib(10)

        assert completed3["status"] == "finished"
        assert completed3["result"] == 128  # 2^7
