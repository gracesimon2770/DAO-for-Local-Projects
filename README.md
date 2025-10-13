# 🏛️ DAO for Local Projects

> **Empowering grassroots decision-making through blockchain governance** 🌱

A decentralized autonomous organization (DAO) smart contract built on Stacks that enables communities to propose, vote on, and fund local projects through democratic decision-making.

## 🌟 Features

- 👥 **Community Membership**: Join the DAO and participate in governance
- 📝 **Project Proposals**: Submit local project ideas for community consideration  
- 🗳️ **Democratic Voting**: Vote on proposals with transparent results
- 💰 **Funding Mechanism**: Approved projects receive funding from community treasury
- 📊 **Project Tracking**: Monitor progress with updates from project leaders
- ⚙️ **Configurable Governance**: Adjustable voting periods and thresholds

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks CLI](https://docs.stacks.co/docs/write-smart-contracts/cli-wallet-quickstart) for deployment

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run tests with Clarinet:
   ```bash
   clarinet test
   ```

## 🎯 Usage

### For Community Members

#### 1. Join the DAO 🤝
```clarity
(contract-call? .dao-for-local-projects join-dao)
```

#### 2. Propose a Local Project 💡
```clarity
(contract-call? .dao-for-local-projects propose-project 
  "Community Garden" 
  "Create a shared garden space for local food production and education"
  u1000000) ;; funding amount in microSTX
```

#### 3. Vote on Proposals 🗳️
```clarity
;; Vote FOR a proposal
(contract-call? .dao-for-local-projects vote-on-proposal u1 true)

;; Vote AGAINST a proposal  
(contract-call? .dao-for-local-projects vote-on-proposal u1 false)
```

#### 4. Execute Approved Proposals ✅
```clarity
(contract-call? .dao-for-local-projects execute-proposal u1)
```

#### 5. Add Project Updates 📈
```clarity
(contract-call? .dao-for-local-projects add-project-update 
  u1 
  "Garden site prepared and seeds planted!")
```

### For Contributors

#### Fund the Treasury 💳
```clarity
(contract-call? .dao-for-local-projects fund-treasury)
```

### For Administrators

#### Configure Voting Parameters ⚙️
```clarity
;; Set voting period (in blocks)
(contract-call? .dao-for-local-projects set-voting-period u1440)

;; Set minimum votes required
(contract-call? .dao-for-local-projects set-min-votes u3)
```

## 📖 Read-Only Functions

Query contract state without transactions:

```clarity
;; Get member information
(contract-call? .dao-for-local-projects get-member u1)

;; Check proposal details
(contract-call? .dao-for-local-projects get-proposal u1)

;; View treasury balance
(contract-call? .dao-for-local-projects get-treasury-balance)

;; Check voting period
(contract-call? .dao-for-local-projects get-voting-period)
```

## 🔄 Workflow

1. **Community Formation** 👥
   - Interested members join the DAO
   - Contributors fund the treasury

2. **Project Ideation** 💭
   - Members propose local projects with funding requests
   - Proposals include title, description, and budget

3. **Democratic Voting** 🗳️
   - Community votes on active proposals
   - Voting period is configurable (default: 1440 blocks)

4. **Execution** 🎯
   - Approved proposals automatically receive funding
   - Project leaders provide regular updates

5. **Accountability** 📊
   - Transparent tracking of project progress
   - Community oversight of funded initiatives

## 🛡️ Security Features

- ✅ Member-only proposal creation and voting
- ✅ One vote per member per proposal
- ✅ Automatic execution based on vote results
- ✅ Treasury protection against unauthorized access
- ✅ Time-bound voting periods

## 🎨 Example Use Cases

- 🌳 **Community Gardens**: Collaborative green spaces
- 🏀 **Recreational Facilities**: Local sports courts and playgrounds  
- 📚 **Educational Programs**: Workshops and skill-sharing initiatives
- 🛤️ **Infrastructure Improvements**: Sidewalks, lighting, and accessibility
- 🎨 **Arts & Culture**: Murals, festivals, and community events
- ♻️ **Sustainability Projects**: Recycling programs and clean energy

## 🤝 Contributing

We welcome contributions to improve the DAO functionality! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

---

*Built with ❤️ for stronger communities through decentralized governance*
