local B = CodexBanking
local QBCore = B.QBCore

local function adminFailure(message)
    return { ok = false, message = message }
end

local function adminOverview()
    local accountStats = B.DB.single([[
        SELECT COUNT(*) AS accounts, COALESCE(SUM(balance), 0) AS ledger_balance
        FROM codex_bank_accounts
    ]], {}) or {}
    local todayVolume = B.DB.scalar('SELECT COALESCE(SUM(amount), 0) FROM codex_bank_transactions WHERE created_at >= CURDATE()', {}) or 0
    local loanStats = B.DB.single([[
        SELECT COUNT(*) AS count, COALESCE(SUM(balance), 0) AS balance
        FROM codex_bank_loans WHERE status IN ('active', 'late', 'defaulted')
    ]], {}) or {}
    local fees = B.DB.query('SELECT bank_id, fee_balance FROM codex_bank_vaults ORDER BY bank_id ASC', {})
    local atmStats = B.DB.single('SELECT COUNT(*) AS count, COALESCE(SUM(fee_balance), 0) AS pending_fees FROM codex_bank_atm_owners', {}) or {}
    local transactions = B.DB.query([[
        SELECT t.id, t.reference, t.type, t.amount, t.fee, t.description, t.actor_cid, t.created_at,
               fa.account_no AS from_account_no, ta.account_no AS to_account_no
        FROM codex_bank_transactions t
        LEFT JOIN codex_bank_accounts fa ON fa.id = t.from_account_id
        LEFT JOIN codex_bank_accounts ta ON ta.id = t.to_account_id
        ORDER BY t.id DESC LIMIT 25
    ]], {})

    local feePercent = tonumber(B.Settings.interBankFeePercent) or tonumber(Config.Transfer.InterBankFeePercent) or 0.005
    return {
        accountCount = tonumber(accountStats.accounts) or 0,
        ledgerBalance = tonumber(accountStats.ledger_balance) or 0,
        todayVolume = tonumber(todayVolume) or 0,
        activeLoans = tonumber(loanStats.count) or 0,
        loanBalance = tonumber(loanStats.balance) or 0,
        atmCount = tonumber(atmStats.count) or 0,
        atmOwnerFees = tonumber(atmStats.pending_fees) or 0,
        feeVaults = fees,
        transactions = transactions,
        interBankFeePercent = feePercent * 100,
        maxTransferFeePercent = tonumber(Config.Admin.MaxRuntimeTransferFeePercent) or 5.0,
        branchCount = #(Config.Branches or {})
    }
end

QBCore.Functions.CreateCallback('codex_banking:server:adminAction', function(source, cb, action, payload, token)
    if not B.Ready then cb(adminFailure('not_ready')) return end
    if type(payload) ~= 'table' then payload = {} end
    local session = B.SessionFor(source, token)
    if not session or session.mode ~= 'admin' or not B.IsAdmin(source) then
        cb(adminFailure('no_permission'))
        return
    end

    if action == 'overview' then
        cb({ ok = true, message = 'admin_overview', overview = adminOverview() })
        return
    end

    if action == 'setInterBankFee' then
        local percent = tonumber(payload.percent)
        local maximum = tonumber(Config.Admin.MaxRuntimeTransferFeePercent) or 5.0
        if not percent or percent < 0 or percent > maximum then
            cb(adminFailure('invalid_amount'))
            return
        end
        local result = B.WithLock(function()
            local fraction = percent / 100
            B.DB.update([[
                INSERT INTO codex_bank_settings (setting_key, setting_value)
                VALUES ('inter_bank_fee_percent', ?)
                ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
            ]], { tostring(fraction) })
            local persisted = tonumber(B.DB.scalar("SELECT setting_value FROM codex_bank_settings WHERE setting_key = 'inter_bank_fee_percent'", {}))
            if not persisted or math.abs(persisted - fraction) > 0.000001 then
                return { ok = false, message = 'server_error' }
            end
            B.Settings.interBankFeePercent = fraction
            print(('^3[codex_banking] Admin %s updated inter-bank transfer fee to %.2f%%.^7'):format(B.GetCitizenId(B.GetPlayer(source)) or tostring(source), percent))
            return { ok = true, message = 'setting_saved', overview = adminOverview() }
        end)
        cb(result)
        return
    end

    cb(adminFailure('unknown_action'))
end)

-- Small public bridge for other QBCore resources. Company money still uses this
-- resource's ledger; these exports deliberately do not alter qb-management funds.
exports('GetJobAccountBalance', function(jobName)
    local account = B.DB.single("SELECT balance FROM codex_bank_accounts WHERE account_type = 'company' AND job_name = ? LIMIT 1", { tostring(jobName) })
    return account and math.floor(tonumber(account.balance) or 0) or 0
end)

exports('AddJobMoney', function(jobName, amount, reason, actorCid)
    amount = B.Number(amount, 1, Config.Security.MaxAmount)
    if not amount then return false end
    local result = B.WithLock(function()
        local account = B.DB.single("SELECT * FROM codex_bank_accounts WHERE account_type = 'company' AND job_name = ? LIMIT 1", { tostring(jobName) })
        if not account then return { ok = false } end
        local currentBalance = tonumber(account.balance) or 0
        local maxBalance = tonumber(account.max_balance) or Config.Accounts.DefaultMaxBalance
        if currentBalance + amount > maxBalance then return { ok = false } end
        local ok = B.DB.transaction({
            { query = 'UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', values = { amount, account.id, amount } },
            { query = [[INSERT INTO codex_bank_transactions (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description) VALUES (?, NULL, ?, ?, 'company_credit', ?, 0, ?)]], values = { B.MakeReference('JOB'), account.id, actorCid or 'system', amount, B.Trim(reason or 'External company credit', 160) } }
        })
        return { ok = ok }
    end)
    return result and result.ok == true
end)

exports('RemoveJobMoney', function(jobName, amount, reason, actorCid)
    amount = B.Number(amount, 1, Config.Security.MaxAmount)
    if not amount then return false end
    local result = B.WithLock(function()
        local account = B.DB.single("SELECT * FROM codex_bank_accounts WHERE account_type = 'company' AND job_name = ? LIMIT 1", { tostring(jobName) })
        if not account or tonumber(account.balance) < amount then return { ok = false } end
        local ok = B.DB.transaction({
            { query = 'UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', values = { amount, account.id, amount } },
            { query = [[INSERT INTO codex_bank_transactions (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description) VALUES (?, ?, NULL, ?, 'company_debit', ?, 0, ?)]], values = { B.MakeReference('JOB'), account.id, actorCid or 'system', amount, B.Trim(reason or 'External company debit', 160) } }
        })
        return { ok = ok }
    end)
    return result and result.ok == true
end)
