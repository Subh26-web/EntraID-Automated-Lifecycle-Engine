# Enterprise Identity Lifecycle Automation Engine (JML) | Microsoft Entra ID

## 📌 Project Overview
Manual identity management causes permission bloat, orphaned accounts, license waste, and compliance violations. 

This project implements an automated, event-driven **Joiner-Mover-Leaver (JML)** identity management architecture using the **Microsoft Graph PowerShell SDK**, **Microsoft Entra ID P2**, and **Attribute-Based Access Control (ABAC)**.

---

## 🏗️ Architecture Workflow

text
[HR System / CSV Feed]
│
▼ (Microsoft Graph PowerShell Engine)
[Microsoft Entra ID Tenant]
├── Scoping: Administrative Units (AU-Engineering / AU-Finance)
├── Entitlements: Dynamic Security Groups (ABAC Evaluation)
├── Cost Optimization: Group-Based Automated Licensing (M365)
└── Security Hardening: Token Revocation & Continuous Access Evaluation (CAE)

---

## ⚙️ Core Technical Capabilities Implemented

1. **Scoped Administrative Delegation (Administrative Units):**
   - Configured `AU-Engineering` and `AU-Finance` to enforce departmental administrative isolation, restricting delegated admins to their respective business units.
2. **Attribute-Based Access Control (ABAC):**
   - Engineered query-driven Dynamic Security Groups: `(user.department -eq "Engineering") and (user.accountEnabled -eq true)`.
   - Automated birthright entitlement provisioning without manual intervention.
3. **Group-Based License Reclamation:**
   - Linked Microsoft 365 licenses directly to dynamic groups. Disabling leaver accounts automatically reclaims enterprise licenses.
4. **Zero Trust Offboarding & Session Invalidation:**
   - Automated account disabling while simultaneously invalidating active OAuth 2.0 refresh tokens and Continuous Access Evaluation (CAE) sessions via `Revoke-MgUserSignInSession`.
5. **Idempotent Automation & Audit Compliance:**
   - Designed the PowerShell automation engine to check existing states before execution and export timestamped CSV audit logs for regulatory attestation.

---

## 📸 Verification & Evidence

### 1. Pre-requisite Configuration
#### Scoped Administrative Containers
![Administrative Units](docs/screenshots/01_EntraID_AdminUnits_Setup.png)

#### Dynamic Security Groups (ABAC)
![Birthright Groups](docs/screenshots/02_EntraID_Birthright_Groups.png)

#### Group-Based Licensing
![Group-Based Licensing](docs/screenshots/03_M365_Group_Based_Licensing.png)

---

### 2. Joiner Phase (Provisioning)
#### Initial Provisioning Execution
![Joiner Execution](docs/screenshots/04_PS_Joiner_Initial_Execution.png)

#### Batch Ingestion & Idempotent Skips
![Batch Provisioning](docs/screenshots/05_PS_Joiner_Batch_Provisioning.png)

#### Provisioned Cloud Identities in Entra ID
![All Users](docs/screenshots/06_EntraID_AllUsers_Provisioned.png)

#### Administrative Unit Assignment
* **Engineering AU:**
  ![AU Engineering](docs/screenshots/07_EntraID_AU_Engineering_Members.png)
* **Finance AU:**
  ![AU Finance](docs/screenshots/08_EntraID_AU_Finance_Members.png)

---

### 3. Mover Phase (Department Transition & Token Revocation)
#### Mover Script Execution
![Mover Execution](docs/screenshots/09_PS_Mover_Process_Execution.png)

#### Post-Move Scoping Verification
* **Finance AU Updated:**
  ![AU Finance Post-Move](docs/screenshots/10_EntraID_AU_Finance_After_Mover.png)
* **Engineering AU Updated:**
  ![AU Engineering Post-Move](docs/screenshots/11_EntraID_AU_Engineering_After_Mover.png)

---

### 4. Leaver Phase (Zero Trust Deprovisioning)
#### Automated Deprovisioning Execution
![Leaver Execution](docs/screenshots/12_PS_Leaver_Process_Execution.png)

#### Disabled Account Status & Revocation Verification
![Account Disabled](docs/screenshots/14_EntraID_Leaver_User_Disabled_Status.png)

#### Administrative Unit Status Post-Offboarding
![AU Post-Offboard](docs/screenshots/15_EntraID_AU_Engineering_Post_Offboarding.png)

---

### 5. Compliance & Regulatory Audit Trail
![Audit Log CSV](docs/screenshots/13_Audit_Log_CSV_Excel_View.png)

---

## 🚀 Repository Layout

text
C:\EntraID-JML-Lab

├── data/
│   └── HR_Feed.csv                   # Mock HR system input data
├── docs/
│   └── screenshots/                  # Verification evidence images
├── logs/
│   └── JML_Audit_Log_*.csv           # Timestamped compliance audit logs
├── scripts/
│   └── IdentityLifecycle.ps1         # Production PowerShell lifecycle engine
└── README.md


