console.log("🚀 The Logger is starting...");

const fs = require("fs");
const path = require("path");
const axios = require("axios");
const config = require("./config.json");

const API_URL = "https://api-galaswap.gala.com/galachain/api";
const LOG_DIR = "allowance_logs";
const CHECK_INTERVAL = 60 * 60 * 1000; // Check every hour 

const WALLET_ADDRESSES = config.WALLET_ADDRESSES;
const DISCORD_WEBHOOK_URL = config.DISCORD_WEBHOOK_URL;

let previousAllowances = {};

function getWalletName(address) {
    return WALLET_ADDRESSES[address] || address;
}

async function sendDiscordEmbed(title, description, color = 3447003) {
    const embed = {
        embeds: [
            {
                title,
                description,
                color,
                timestamp: new Date().toISOString(),
                footer: { text: "Gala Chain Allowance Logger" },
            },
        ],
    };

    try {
        await axios.post(DISCORD_WEBHOOK_URL, embed, {
            headers: { "Content-Type": "application/json" },
        });
        console.log(`✅ Discord alert sent: ${title}`);
    } catch (error) {
        console.error("❌ Failed to send Discord alert:", error.message);
    }
}

function logDailyReward(wallet, reward) {
    const now = new Date();
    const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const dateString = now.toISOString().split("T")[0];
    const walletName = getWalletName(wallet);
    const walletDir = path.join(LOG_DIR, walletName.replace(/\s+/g, "_"));
    const filePath = path.join(walletDir, `${yearMonth}.csv`);

    if (!fs.existsSync(walletDir)) {
        fs.mkdirSync(walletDir, { recursive: true });
    }

    const logEntry = `${dateString},+${reward}\n`;
    if (!fs.existsSync(filePath)) {
        fs.writeFileSync(filePath, "Date,Reward\n" + logEntry);
    } else {
        fs.appendFileSync(filePath, logEntry);
    }
}

async function sendMonthlyCSV(wallet) {
    const now = new Date();
    const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const walletName = getWalletName(wallet);
    const walletDir = path.join(LOG_DIR, walletName.replace(/\s+/g, "_"));
    const filePath = path.join(walletDir, `${yearMonth}.csv`);

    if (!fs.existsSync(filePath)) return;

    const fileContent = fs.readFileSync(filePath, "utf8");
    const lines = fileContent.split("\n").slice(1).filter(line => line);
    const totalReward = lines.reduce((sum, line) => sum + parseFloat(line.split(",")[1]), 0);
    
    fs.appendFileSync(filePath, `Total,${totalReward}\n`);

    const fileData = fs.readFileSync(filePath);
    const fileBuffer = Buffer.from(fileData);
    const formData = new FormData();
    formData.append("file", fileBuffer, `${yearMonth}.csv`);

    try {
        await axios.post(DISCORD_WEBHOOK_URL, formData, {
            headers: { "Content-Type": "multipart/form-data" },
        });
        console.log(`✅ Monthly CSV sent for ${walletName}`);
    } catch (error) {
        console.error("❌ Failed to send CSV file:", error.message);
    }
}

async function getCorrectAllowanceBalance(wallet) {
    try {
        const response = await axios.post(`${API_URL}/asset/token-contract/FetchAllowances`, {
            grantedTo: wallet,
            collection: "GALA",
        });

        if (!response.data || !response.data.Data) return null;

        let totalRemaining = 0;
        const currentTime = Date.now();

        response.data.Data.forEach(allowance => {
            const quantity = parseFloat(allowance.quantity) || 0;
            const quantitySpent = parseFloat(allowance.quantitySpent) || 0;
            const remaining = quantity - quantitySpent;

            if (remaining > 0 && (allowance.expires === 0 || allowance.expires > currentTime)) {
                totalRemaining += remaining;
            }
        });

        return totalRemaining;
    } catch (error) {
        console.error(`❌ Error fetching allowance for ${wallet}:`, error.message);
        return null;
    }
}

async function checkAllowanceBalances() {
    const now = new Date();
    const isMonthEnd = now.getDate() === new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    
    for (const wallet of Object.keys(WALLET_ADDRESSES)) {
        const totalRemaining = await getCorrectAllowanceBalance(wallet);
        if (totalRemaining === null) continue;

        if (previousAllowances[wallet] !== undefined && totalRemaining !== previousAllowances[wallet]) {
            const diff = totalRemaining - previousAllowances[wallet];
            const walletName = getWalletName(wallet);

            if (diff > 0) {
                await sendDiscordEmbed(
                    "🎉 Daily Reward Received",
                    `🔹 **Wallet:** \`${walletName}\`\n` +
                    `🔹 **Previous:** ${previousAllowances[wallet].toLocaleString()} GALA\n` +
                    `🔹 **New:** ${totalRemaining.toLocaleString()} GALA\n` +
                    `🔹 **Reward:** 🟢 +${diff.toLocaleString()} GALA`,
                    0x2ecc71
                );
                logDailyReward(wallet, diff);
            }
        }
        previousAllowances[wallet] = totalRemaining;

        if (isMonthEnd) {
            await sendMonthlyCSV(wallet);
        }
    }
}

async function main() {
    console.log("✅ The Logger has started!");

    await checkAllowanceBalances();

    setInterval(async () => {
        console.log("🔄 Checking Allowances...");
        await checkAllowanceBalances();
    }, CHECK_INTERVAL);
}

main();
