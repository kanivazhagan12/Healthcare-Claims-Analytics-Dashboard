---Healthcare DashBoard--

--Imported csv FILE
--creating fact and Dimension tables 
---Dim_Patient
CREATE TABLE Dim_Patient (
    PatientKey INT PRIMARY KEY IDENTITY(1,1),
    PatientID VARCHAR(50),
    PatientAge INT,
    PatientGender CHAR(1),
    PatientIncome DECIMAL(10, 2),
    MaritalStatus VARCHAR(20),
    EmploymentStatus VARCHAR(50)
)

INSERT INTO Dim_Patient (PatientID, PatientAge, PatientGender, PatientIncome, MaritalStatus, EmploymentStatus)
SELECT PatientID, MAX(PatientAge), MAX(PatientGender), MAX(PatientIncome), MAX(PatientMaritalStatus), MAX(PatientEmploymentStatus)
FROM Staging_RawClaims
GROUP BY PatientID;

--Dim_Provider
CREATE TABLE Dim_Provider (
    ProviderKey INT PRIMARY KEY IDENTITY(1,1),
    ProviderID VARCHAR(50),
    ProviderSpecialty VARCHAR(50),
    ProviderLocation VARCHAR(50)
)

INSERT INTO Dim_Provider (ProviderID, ProviderSpecialty, ProviderLocation)
SELECT ProviderID, MAX(ProviderSpecialty), MAX(ProviderLocation)
FROM Staging_RawClaims
GROUP BY ProviderID;
--Dim_Payer
CREATE TABLE Dim_Payer(
    PayerKey INT PRIMARY KEY IDENTITY(1,1),
    PayerID VARCHAR(50),
    PayerName VARCHAR(50),
    PayerPlan VARCHAR(50)
    )
	
INSERT INTO Dim_Payer(PayerID, PayerName, PayerPlan)
SELECT PayerID, PayerName, PayerPlanType
FROM Staging_RawClaims
GROUP BY PayerID, PayerName, PayerPlanType;

--Dim_Claims
CREATE TABLE Dim_Claims (
    ClaimKey INT PRIMARY KEY IDENTITY(1,1),
    ClaimID VARCHAR(100),
    POS INT,
    DiagnosisCode VARCHAR(50),
    ProcedureCode VARCHAR(50),
    ClaimStatus VARCHAR(50),
    DenialCode VARCHAR(50),
    DenialReason VARCHAR(50),
    ClaimType VARCHAR(50),
    ClaimSubmissionMethod VARCHAR(50)
)

INSERT INTO Dim_Claims (ClaimID, POS, DiagnosisCode, ProcedureCode, ClaimStatus, DenialCode, DenialReason, ClaimType, ClaimSubmissionMethod)
SELECT ClaimID, POS, DiagnosisCode, ProcedureCode, ClaimStatus, 
       ISNULL(DenialCode, 'N/A'), ISNULL(DenialReason, 'None'), 
       ClaimType, ClaimSubmissionMethod
FROM Staging_RawClaims
GROUP BY ClaimID, POS, DiagnosisCode, ProcedureCode, ClaimStatus, DenialCode, DenialReason, ClaimType, ClaimSubmissionMethod;
--Dim_Date

CREATE TABLE Dim_Date(
DateKey INT PRIMARY KEY,
FullDate DATE NOT NULL,
[Year] INT NOT NULL,
[Quarter] INT NOT NULL,
[Month] INT NOT NULL,
[MonthName] VARCHAR(50) NOT NULL,
[Day] INT NOT NULL
)
DECLARE @StartDate  DATE='2020-01-01'
DECLARE @EndDate    DATE='2030-12-31';

WITH DateCTE AS(
        SELECT @StartDate AS CurrentDate
UNION ALL
        SELECT DATEADD(DAY,1,CurrentDate)
        FROM DateCTE
        WHERE CurrentDate<@EndDate
)
INSERT INTO Dim_Date(DateKey,FullDate,[Year],[Quarter],[Month],[MonthName],[Day])
SELECT
    CAST(FORMAT(CurrentDate,'yyyyMMdd') AS INT),
    CurrentDate,
    YEAR(CurrentDate),
    DATEPART(QUARTER, CurrentDate),
    MONTH(CurrentDate),
    DATENAME(MONTH, CurrentDate),
    DAY(CurrentDate)
    FROM DateCTE
OPTION(MAXRECURSION 0)

--Fact_claims

 CREATE TABLE Fact_Claims(
FactKey INT PRIMARY KEY IDENTITY(1,1),
PatientKey INT REFERENCES Dim_Patient(PatientKey),
ProviderKey INT REFERENCES Dim_Provider(ProviderKey),
PayerKey INT REFERENCES Dim_Payer(PayerKey),
ClaimKey INT REFERENCES Dim_Claims(ClaimKey),
ServiceDateKey INT REFERENCES Dim_Date(DateKey),
ReceivedDateKey INT REFERENCES Dim_Date(DateKey),
AdjudicationDateKey INT REFERENCES Dim_Date(DateKey),
LastActivityDateKey INT REFERENCES Dim_Date(DateKey),
BilledAmount DECIMAL(10,2),
AllowedAmount DECIMAL(10,2),
PaidAmount DECIMAL(10,2),
PRAmount DECIMAL(10,2),
CreatedTimestamp DATETIME DEFAULT GETDATE()
)

INSERT INTO Fact_Claims (
    PatientKey, ProviderKey, PayerKey, ClaimKey, 
    ServiceDateKey, ReceivedDateKey, AdjudicationDateKey, LastActivityDateKey,
    BilledAmount, AllowedAmount, PaidAmount, PRAmount
)
SELECT 
    p.PatientKey, 
    pr.ProviderKey, 
    dp.PayerKey, 
    dc.ClaimKey,
    -- Date Keys
    CAST(FORMAT(s.DateOfService, 'yyyyMMdd') AS INT),
    CAST(FORMAT(s.ClaimReceiveDate, 'yyyyMMdd') AS INT),
    CAST(FORMAT(s.AdjudicationDate, 'yyyyMMdd') AS INT),
    CAST(FORMAT(s.LastActivityDate, 'yyyyMMdd') AS INT),
    s.BilledAmount, 
    s.AllowedAmount, 
    s.PaidAmount, 
    s.PR
FROM Staging_RawClaims s
JOIN Dim_Patient p  ON s.PatientID = p.PatientID
JOIN Dim_Provider pr ON s.ProviderID = pr.ProviderID
-- Multiple JOIN 1: Match Payer ID AND Plan (HMO/PPO)
JOIN Dim_Payer dp   ON s.PayerID = dp.PayerID 
                   AND s.PayerPlanType = dp.PayerPlan
-- Multiple JOIN 2: Match Claim ID AND Procedure (Line-Level)
JOIN Dim_Claims dc  ON s.ClaimID = dc.ClaimID 
                   AND s.ProcedureCode = dc.ProcedureCode;
				   
--OutstandingDays

ALTER TABLE Fact_Claims
ADD DaysOutstanding AS (
    DATEDIFF(day, 
        CAST(CAST(ReceivedDateKey AS VARCHAR(8)) AS DATE), 
        COALESCE(
            CAST(CAST(AdjudicationDateKey AS VARCHAR(8)) AS DATE), 
            CAST(CAST(LastActivityDateKey AS VARCHAR(8)) AS DATE)
        )
    )
)

	