import sys
import pypdf

try:
    reader = pypdf.PdfReader('Rider_Payroll_ERP_SRS_v1.pdf')
    text = ''
    for page in reader.pages:
        text += page.extract_text() + '\n'

    with open('req.txt', 'w', encoding='utf-8') as f:
        f.write(text)
    print("Done")
except Exception as e:
    print(f"Error: {e}")
