console.log("🚀 The Logger is starting...");

const fs = require("fs");
const path = require("path");
const axios = require("axios");
const config = require("./config.json");

const API_URL = "https://api-galaswap.gala.com/galachain/api";
const LOG_DIR = "allowance_logs";
const CHECK_INTERVAL = 60 * 1000; // Check every 60 seconds

const WALLET_ADDRESSES = config.WALLET_ADDRESSES;
const DISCORD_WEBHOOK_URL = config.DISCORD_WEBHOOK_URL;

let previousAllowances = {};

/**
 * Gets the display name of a wallet, falls back to the address if not found.
 */
function getWalletName(address) {
    return WALLET_ADDRESSES[address] || address;
}

/**
 * Sends an alert to Discord with an embedded message.
 */
async function sendDiscordEmbed(title, description, color = 3447003) {
    const embed = {
        embeds: [
            {
                title,
                description,
                color,
                timestamp: new Date().toISOString(),
                footer: { text: "Gala Chain Balance Logger" },
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

/**
 * Logs allowance changes to a CSV file.
 */
function logAllowance(wallet, change) {
    const now = new Date();
    const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    const dateString = now.toISOString().split("T")[0];
    const walletName = getWalletName(wallet);
    const walletDir = path.join(LOG_DIR, walletName.replace(/\s+/g, "_"));
    const filePath = path.join(walletDir, `${yearMonth}.csv`);

    if (!fs.existsSync(walletDir)) {
        fs.mkdirSync(walletDir, { recursive: true });
    }

    const logEntry = `${dateString},${change}\n`;
    if (!fs.existsSync(filePath)) {
        fs.writeFileSync(filePath, "Date,Change\n" + logEntry);
    } else {
        fs.appendFileSync(filePath, logEntry);
    }
}

/**
 * Fetches the correct allowance balance from the API.
 */
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

/**
 * Checks for allowance changes and sends notifications.
 */
async function checkAllowanceBalances() {
    for (const wallet of Object.keys(WALLET_ADDRESSES)) {
        const totalRemaining = await getCorrectAllowanceBalance(wallet);
        if (totalRemaining === null) continue;

        if (previousAllowances[wallet] !== undefined && totalRemaining !== previousAllowances[wallet]) {
            const diff = totalRemaining - previousAllowances[wallet];
            const changeText = diff > 0 ? `🟢 +${diff.toLocaleString()}` : `🔴 ${diff.toLocaleString()}`;
            const walletName = getWalletName(wallet);

            await sendDiscordEmbed(
                "📦 Allowance Updated",
                `🔹 **Wallet:** \`${walletName}\`\n` +
                `🔹 **Previous:** ${previousAllowances[wallet].toLocaleString()} GALA\n` +
                `🔹 **New:** ${totalRemaining.toLocaleString()} GALA\n` +
                `🔹 **Change:** ${changeText}`,
                diff > 0 ? 0x2ecc71 : 0xe74c3c
            );

            logAllowance(wallet, diff);
        }
        previousAllowances[wallet] = totalRemaining;
    }
}

/**
 * Starts the bot and runs the allowance checks periodically.
 */
async function main() {
    console.log("✅ The Logger has started!");

    await checkAllowanceBalances(); // Initial check on startup

    setInterval(async () => {
        console.log("🔄 Checking Allowances...");
        await checkAllowanceBalances();
    }, CHECK_INTERVAL);
}

main();
