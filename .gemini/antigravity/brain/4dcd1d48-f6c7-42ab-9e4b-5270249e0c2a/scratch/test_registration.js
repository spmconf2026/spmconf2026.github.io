// Using built-in fetch in Node 22+

const googleWebAppUrl = 'https://script.google.com/macros/s/AKfycby5ET7MObVIHlnJghJosK5jVBSrXE5vNeZ5SRBHITlpcLZTNUn7_BFpB_7AD_EHnJ-N/exec';

const names = ['James Smith', 'Maria Garcia', 'Robert Johnson', 'Maria Rodriguez', 'David Smith', 'Mary Williams', 'Maria Hernandez', 'Robert Smith', 'Maria Martinez', 'James Johnson', 'Jeffery Mason', 'Alperen Arslan', 'John Doe', 'Jane Doe', 'Michael Brown', 'Sarah Wilson', 'Emily Davis', 'Chris Evans', 'Tony Stark', 'Steve Rogers', 'Natasha Romanoff', 'Bruce Banner', 'Wanda Maximoff', 'Vision', 'Peter Parker', 'Stephen Strange', 'Thor Odinson', 'Loki Laufeyson', 'Arthur Curry', 'Diana Prince'];
const affiliations = ['MIT', 'Stanford', 'ITU', 'ETH Zurich', 'Oxford', 'Cambridge', 'TUM', 'UC Berkeley', 'Harvard', 'EPFL'];
const conferences = ['SPM', 'SMI'];
const packages = ['FULL', 'STUDENT', 'DAILY', 'DINNER_ONLY'];
const submissionTypes = ['Full Paper', 'Presentation-Only', 'Poster', 'External Attendee (No Paper)'];

const isEarlyBird = new Date() <= new Date('2026-06-06T23:59:59+03:00');
const BANQUET_ADDON_PRICE = isEarlyBird ? 200 : 250;

const registrationPackages = {
    "FULL": {
        label: "Full",
        price: isEarlyBird ? 600 : 700,
        banquetIncluded: true,
        paperCoverage: true,
        canAddStudents: true,
        defaultDays: 'Full'
    },
    "STUDENT": {
        label: "Student",
        price: isEarlyBird ? 400 : 470,
        banquetIncluded: true,
        paperCoverage: false,
        defaultDays: 'Full'
    },
    "DAILY": {
        label: "Daily Pass",
        pricePerDay: isEarlyBird ? 200 : 250,
        price: isEarlyBird ? 200 : 250,
        banquetIncluded: false,
        paperCoverage: false,
        externalOnly: true,
        requiresDaySelection: true,
        dayLimit: 4
    },
    "DINNER_ONLY": {
        label: "Conference Dinner Only",
        price: isEarlyBird ? 200 : 250,
        banquetIncluded: true,
        paperCoverage: false,
        externalOnly: true,
        requiresDaySelection: false,
        dinnerOnly: true,
        defaultDays: 'Not Applicable'
    }
};

function getStudentTotalCost(count) {
    if (count <= 0) return 0;
    const base1 = isEarlyBird ? 400 : 470;
    const base2 = isEarlyBird ? 310 : 370;
    const base3 = isEarlyBird ? 270 : 320;
    if (count === 1) return base1;
    if (count === 2) return base2 * 2;
    return base3 * count;
}

function buildTransferNote(pkgCode, confType, studentCount, dayCount, banquetAddon, paperIdRaw) {
    let paperId = '000';
    if (paperIdRaw && paperIdRaw !== 'Not Applicable' && paperIdRaw !== 'External Attendee') {
        const numericId = parseInt(paperIdRaw, 10);
        if (!isNaN(numericId)) {
            paperId = String(numericId).padStart(3, '0');
        }
    }

    let X = '1';
    if (pkgCode === 'STUDENT') X = '2';
    else if (pkgCode === 'DAILY') X = '3';
    else if (pkgCode === 'DINNER_ONLY') X = '4';

    let Y = '0';
    if (pkgCode === 'FULL') {
        Y = String(studentCount);
    } else if (pkgCode === 'DAILY') {
        Y = String(dayCount);
    }

    let Z = (pkgCode === 'FULL' || pkgCode === 'STUDENT' || pkgCode === 'DINNER_ONLY' || banquetAddon) ? '1' : '0';

    return 'Conditional-donation-Conference-' + confType + '-' + paperId + '-' + X + Y + Z;
}

async function sendTestData(i) {
    const uploaderName = names[i % names.length];
    const email = uploaderName.toLowerCase().replace(' ', '.') + i + '@example.com';
    const affiliation = affiliations[Math.floor(Math.random() * affiliations.length)];
    const confType = conferences[Math.floor(Math.random() * conferences.length)];
    const pkgCode = packages[Math.floor(Math.random() * packages.length)];
    const selectedPackage = registrationPackages[pkgCode];
    
    let studentCount = 0;
    let students = ['', '', '', '', ''];
    if (pkgCode === 'FULL') {
        studentCount = Math.floor(Math.random() * 3); // 0, 1, 2
        for (let s = 0; s < studentCount; s++) {
            students[s] = names[(i + s + 10) % names.length] + ' (Student)';
        }
    }

    let dayCount = 0;
    let attendanceDays = '';
    if (pkgCode === 'DAILY') {
        dayCount = Math.floor(Math.random() * 2) + 1; // 1 or 2
        attendanceDays = Array.from({length: dayCount}, (_, k) => (6 + k).toString()).join(', ');
    } else {
        attendanceDays = selectedPackage.defaultDays;
    }

    const banquetAddon = (pkgCode === 'DAILY' && Math.random() > 0.5);
    
    let subType = submissionTypes[Math.floor(Math.random() * submissionTypes.length)];
    let subNum = (subType === 'External Attendee (No Paper)' || selectedPackage.externalOnly) ? 'Not Applicable' : Math.floor(Math.random() * 500).toString();
    let subTitle = (subNum === 'Not Applicable') ? 'Not Applicable' : 'Research Paper on Geometry ' + i;

    let total = selectedPackage.price;
    if (pkgCode === 'DAILY') total = dayCount * selectedPackage.pricePerDay;
    if (banquetAddon) total += BANQUET_ADDON_PRICE;
    if (studentCount > 0) total += getStudentTotalCost(studentCount);

    const note = buildTransferNote(pkgCode, confType, studentCount, dayCount, banquetAddon, subNum);

    const requestData = {
        fileName: 'test_receipt_' + i + '.pdf',
        mimeType: 'application/pdf',
        fileData: 'JVBERi0xLjQKJcOkw7zDtsOfCjIgMCBvYmoKPDwvTGVuZ3RoIDMgMCBSL0ZpbHRlci9GbGF0ZURlY29kZT4+CnN0cmVhbQp4nGNgYFBgYDBgMABhAAABAwBEZW5kc3RyZWFtCmVuZ29iagozIDAgb2JqCjExCmVuZG9iago0IDAgb2JqCjw8L1R5cGUvUGFnZXMvQ291bnQgMS9LaWRzWzEgMCBSXT4+CmVuZG9iago1IDAgb2JqCjw8L1R5cGUvQ2F0YWxvZy9QYWdlcyA0IDAgUj4+CmVuZG9iago2IDAgb2JqCjw8L1Byb2R1Y2VyICh0ZXN0KS9DcmVhdGlvbkRhdGUgKEQ6MjAyNjA1MDcxOTI0MjhaKSA+PgplbmRvYmoKeHJlZgowIDcKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE5IDAwMDAwIG4gCjAwMDAwMDAwNzggMDAwMDAgbiAKMDAwMDAwMDE1NCAwMDAwMCBuIAowMDAwMDAwMTczIDAwMDAwIG4gCjAwMDAwMDAyMjggMDAwMDAgbiAKMDAwMDAwMDI3NyAwMDAwMCBuIAp0cmFpbGVyCjw8L1NpemUgNy9Sb290IDUgMCBSL0luZm8gNiAwIFI+PgpzdGFydHhyZWYKMzUwCiUlRU9GCg==',
        uploaderName: uploaderName,
        contactEmail: email,
        affiliation: affiliation,
        registrationPackage: selectedPackage.label,
        packageCode: pkgCode,
        registrationQuantity: 1 + studentCount,
        registrationUnitPrice: selectedPackage.price,
        calculatedPaymentTotal: total.toString(),
        recommendedTransferNote: note,
        banquetIncluded: (selectedPackage.banquetIncluded || banquetAddon) ? 'Yes' : 'No',
        paperCoverage: (selectedPackage.paperCoverage) ? 'Yes' : 'No',
        attendanceDays: attendanceDays,
        conferenceType: confType,
        submissionType: subType,
        submissionNumber: subNum,
        submissionTitle: subTitle,
        student1Name: students[0],
        student2Name: students[1],
        student3Name: students[2],
        student4Name: students[3],
        student5Name: students[4],
        studentCount: studentCount
    };

    console.log(`Sending data for ${uploaderName} (${i+1}/30)...`);
    
    try {
        const response = await fetch(googleWebAppUrl, {
            method: 'POST',
            body: JSON.stringify(requestData)
        });
        // Since the backend uses mode: 'no-cors' in the browser, 
        // we might not get a readable response but we can check if it didn't throw.
        console.log(`Success for ${uploaderName}`);
    } catch (error) {
        console.error(`Error for ${uploaderName}:`, error);
    }
}

async function runTest() {
    for (let i = 0; i < 30; i++) {
        await sendTestData(i);
        // Add a small delay to avoid hitting rate limits too hard
        await new Promise(resolve => setTimeout(resolve, 500));
    }
    console.log('Finished sending 30 test data entries.');
}

runTest();
