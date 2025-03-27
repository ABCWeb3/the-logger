# The Logger

🚀 **The Logger** is a powerful GalaChain monitoring bot that tracks token allowances and logs balance changes. It sends real-time notifications to Discord and keeps organized logs for easy tracking.

---

## 📌 Features
- ✅ **Tracks Allowances**: Monitors GALA token allowances on GalaChain.
- 🔔 **Discord Notifications**: Sends real-time alerts on balance changes.
- 📊 **CSV Logging**: Organizes logs by wallet and month for easy reference.
- ⏱ **Automated Monitoring**: Runs on an interval to check for updates continuously.
- 🏷 **Custom Wallet Names**: Assign friendly names to wallets for easy identification.

---

## 🚀 Installation

### 1️⃣ Clone the Repository
```sh
sudo apt update
sudo apt upgrade
sudo apt install curl
git clone https://github.com/your-repo/the-logger.git
cd the-logger
```

### 2️⃣ Install Dependencies
```sh
npm install
```

### 3️⃣ Configure the Bot
Edit the `config.json` file:
```json
{
  "WALLET_ADDRESSES": {
    "client|example_wallet_1": "Main Wallet",
    "client|example_wallet_2": "Trading Account"
  },
  "DISCORD_WEBHOOK_URL": "https://discord.com/api/webhooks/your_webhook_url"
}
```

- Replace wallet addresses with your own.
- Set up your Discord webhook URL.

### 4️⃣ Start the Bot
```sh
npm start
```

---

## 🔍 How It Works
1. The bot fetches token allowances from the GalaChain API.
2. It compares the current balance with the previous one.
3. If a change is detected, it logs the update and sends an alert to Discord.
4. Data is stored in CSV format, categorized by wallet and month.

---

## 📝 Logging Format
Each wallet gets a separate log file under `allowance_logs/`. The data is recorded in CSV format:
```
Date,Amount,Total Monthly
2025-03-26,500,1500
2025-03-27,-200,1300
```

---

## 🛠 Future Enhancements
- 🌐 Web dashboard for real-time visualization.
- 📈 Advanced analytics on allowance usage.
- 🔄 Multi-currency support.

---

## 👨‍💻 Developed by
**ABC**

---

## 💖 Support the Project
If you find **The Logger** useful, consider donating to support future development:
**Donate:** `eth|8C1C40a9df32D7460cb387FBf6Ede6cD9Ec5689e`

---

## 📜 License
This project is licensed under the **MIT License**.

