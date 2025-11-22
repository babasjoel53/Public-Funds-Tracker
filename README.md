# 💰 Public Funds Tracker

A transparent blockchain-based smart contract for tracking public fund allocation and disbursement on the Stacks blockchain.

## ✨ Features

🔐 **Owner Control**: Only authorized contract owner can manage treasury and projects  
📊 **Project Management**: Create, track, and close public funding projects  
💸 **Disbursement Tracking**: Record all fund disbursements with complete transparency  
👥 **Multi-Role System**: Support for project managers and auditors  
⏸️ **Emergency Controls**: Pause/resume projects when needed  
📈 **Real-time Analytics**: Track utilization rates and remaining funds

## 🚀 Quick Start


### Installation
```bash
git clone <repository-url>
cd Public-Funds-Tracker
clarinet check
```

## 📋 Contract Functions

### 🏛️ Treasury Management
- `initialize-treasury(initial-amount)` - Set up initial treasury balance
- `deposit-funds(amount)` - Add funds to treasury
- `get-treasury-balance()` - View current treasury balance

### 📝 Project Operations
- `create-project(name, description, allocated-amount, manager)` - Create new project
- `close-project(project-id)` - Close project and return unused funds
- `emergency-pause-project(project-id)` - Pause project operations
- `resume-project(project-id)` - Resume paused project

### 💳 Disbursement Management
- `approve-disbursement(project-id, amount, recipient, purpose)` - Approve fund disbursement
- `get-disbursement(disbursement-id)` - View disbursement details

### 👨‍💼 Access Control
- `authorize-auditor(auditor)` - Grant auditor permissions
- `revoke-auditor(auditor)` - Remove auditor permissions
- `get-project-manager(project-id)` - View project manager

### 📊 Analytics & Reporting
- `get-project(project-id)` - Get complete project information
- `get-project-utilization(project-id)` - Calculate spending percentage
- `get-remaining-funds(project-id)` - View unspent project funds
- `get-total-allocated-funds()` - Total funds allocated across all projects
- `get-total-spent-funds()` - Total funds spent across all projects

## 🎯 Usage Examples

### Initialize Contract
```clarity
(contract-call? .Public-Funds-Tracker initialize-treasury u1000000)
```

### Create Public Project
```clarity
(contract-call? .Public-Funds-Tracker create-project 
    "Road Infrastructure" 
    "Highway renovation project for downtown area" 
    u500000
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Approve Disbursement
```clarity
(contract-call? .Public-Funds-Tracker approve-disbursement 
    u1 
    u50000 
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7
    "Materials procurement for road construction")
```

### Check Project Status
```clarity
(contract-call? .Public-Funds-Tracker get-project u1)
(contract-call? .Public-Funds-Tracker get-project-utilization u1)
```

## 🏗️ Contract Architecture

### Data Structures
- **Projects**: Store project metadata, allocation, and spending
- **Disbursements**: Track all fund distributions with full audit trail
- **Project Managers**: Map projects to responsible managers
- **Authorized Auditors**: Maintain list of permitted auditors

### Security Features
- Owner-only treasury management
- Manager-level project disbursement approval
- Emergency pause functionality
- Input validation and error handling

## 🔒 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner-only function called by non-owner |
| u101 | Unauthorized access attempt |
| u102 | Requested resource not found |
| u103 | Insufficient funds for operation |
| u104 | Invalid amount provided |
| u105 | Resource already exists |
| u106 | Project is inactive/paused |


---

Built with ❤️ for transparency in public fund management
