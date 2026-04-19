from pprint import pprint

from main import upload_dynamic_excel, DynamicExcelUploadRequest


def run_test():
    # Use the seeded test rider (created earlier by seed_test_rider.py)
    rows = [
        {
            "rider id": "SEED_TEST_001",
            "name": "Seed Test Rider",
            "phone": "0500000000",
            "bike no": "TESTBIKE123",
            "company": "talabat",
            "giving date": "2026-03-01"
        }
    ]

    req = DynamicExcelUploadRequest(rows=rows)

    # Call the handler directly and provide a user with ACCOUNTANT role
    result = upload_dynamic_excel(req, user={"role": "accountant", "id": "test-user"})
    pprint(result)


if __name__ == "__main__":
    run_test()
