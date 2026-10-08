local B = CodexBanking
local QBCore = B.QBCore
local Actions = {}

local function failure(message)
    return { ok = false, message = message }
end

local function success(message, extra)
    local result = extra or {}
    result.ok = true
    result.message = message
    return result
end

local function queryObject(query, values)
    return { query = query, values = values or {} }
end

local function transactionLog(fromId, toId, actorCid, kind, amount, fee, description)
    local fromSql = fromId ~= nil and '?' or 'NULL'
    local toSql = toId ~= nil and '?' or 'NULL'
    local actorSql = actorCid ~= nil and '?' or 'NULL'
    local values = { B.MakeReference(kind) }
    if fromId ~= nil then values[#values + 1] = fromId end
    if toId ~= nil then values[#values + 1] = toId end
    if actorCid ~= nil then values[#values + 1] = actorCid end
    values[#values + 1] = kind
    values[#values + 1] = math.floor(tonumber(amount) or 0)
    values[#values + 1] = math.floor(tonumber(fee) or 0)
    values[#values + 1] = B.Trim(description or '', 160)
    return queryObject(([[
        INSERT INTO codex_bank_transactions
            (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description)
        VALUES (?, %s, %s, %s, ?, ?, ?, ?)
    ]]):format(fromSql, toSql, actorSql), values)
end

local function vaultQuery(bankId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not bankId then return nil end
    return queryObject([[
        INSERT INTO codex_bank_vaults (bank_id, fee_balance) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE fee_balance = fee_balance + VALUES(fee_balance)
    ]], { bankId, amount })
end

local function safeQueries(queries)
    local kept = {}
    for _, query in ipairs(queries) do
        if query then kept[#kept + 1] = query end
    end
    return kept
end

local function branchRequired(session)
    return session and session.mode == 'branch'
end

local function atmRequired(session)
    return session and session.mode == 'atm' and session.cardId ~= nil
end

local function branchMatches(session, bankId)
    return branchRequired(session) and (not bankId or session.bankId == bankId)
end

local function getAccount(source, accountId)
    local account, err, player, citizenid = B.AccountAccess(source, accountId)
    if not account then return nil, err end
    return account, nil, player, citizenid
end

local function currentDailySpend(accountId, citizenid)
    local usageType = ('account_%s'):format(tostring(accountId))
    local amount = B.DB.scalar([[
        SELECT amount FROM codex_bank_daily_usage
        WHERE citizenid = ? AND usage_type = ? AND usage_day = CURDATE()
        LIMIT 1
    ]], { citizenid, usageType })
    return math.max(0, math.floor(tonumber(amount) or 0))
end

local function accountUsageQuery(accountId, citizenid, amount)
    return queryObject([[
        INSERT INTO codex_bank_daily_usage (citizenid, usage_type, usage_day, amount)
        VALUES (?, ?, CURDATE(), ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], { citizenid, ('account_%s'):format(tostring(accountId)), amount })
end

local function canSpend(account, citizenid, amount, permission)
    if permission == 'transfer' and not account.canTransfer then
        return false, 'no_permission'
    end
    if permission == 'withdraw' and not account.canWithdraw then
        return false, 'no_permission'
    end
    if permission == 'manage' and not account.canManage then
        return false, 'no_permission'
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if account.balance < amount then return false, 'insufficient_funds' end

    local accountLimit = math.max(0, math.floor(tonumber(account.daily_limit) or Config.Accounts.DefaultDailyLimit))
    local memberLimit = math.max(0, math.floor(tonumber(account.member_daily_limit) or accountLimit))
    local effectiveLimit = math.min(accountLimit, memberLimit)
    local spent = currentDailySpend(account.id, citizenid)
    if effectiveLimit > 0 and spent + amount > effectiveLimit then
        return false, 'daily_limit'
    end
    if effectiveLimit == 0 then
        return false, 'daily_limit'
    end
    return true
end

local function memberSpendQuery(accountId, citizenid, amount)
    return queryObject([[
        UPDATE codex_bank_account_members
        SET daily_spent = IF(daily_spent_date = CURDATE(), daily_spent + ?, ?),
            daily_spent_date = CURDATE()
        WHERE account_id = ? AND citizenid = ?
    ]], { amount, amount, accountId, citizenid })
end

local function createAccount(bankId, accountType, label, ownerCid, jobName, balance, options)
    options = options or {}
    local accountNo = options.accountNo or B.AccountNumber(bankId)
    if not accountNo then return nil end
    local ownerSql = ownerCid ~= nil and '?' or 'NULL'
    local jobSql = jobName ~= nil and '?' or 'NULL'
    local values = { accountNo, bankId, accountType, B.Trim(label, 64) }
    if ownerCid ~= nil then values[#values + 1] = ownerCid end
    if jobName ~= nil then values[#values + 1] = jobName end
    local numericValues = {
        math.floor(tonumber(balance) or 0),
        math.floor(tonumber(options.dailyLimit) or Config.Accounts.DefaultDailyLimit),
        math.floor(tonumber(options.maxBalance) or Config.Accounts.DefaultMaxBalance),
        math.floor(tonumber(options.level) or 1),
        math.floor(tonumber(options.savingsTier) or 0),
        math.floor(tonumber(options.savingsGoal) or 0),
        B.Trim(options.savingsGoalLabel or '', 64)
    }
    for _, value in ipairs(numericValues) do values[#values + 1] = value end
    local id = B.DB.insert(([[
        INSERT INTO codex_bank_accounts
            (account_no, bank_id, account_type, label, owner_cid, job_name, balance,
             daily_limit, max_balance, account_level, savings_tier, savings_goal, savings_goal_label, last_interest_day)
        VALUES (?, ?, ?, ?, %s, %s, ?, ?, ?, ?, ?, ?, ?, CURDATE())
    ]]):format(ownerSql, jobSql), values)
    if not id then return nil end
    if options.memberCid then
        local role = options.role or 'owner'
        local definition = Config.Accounts.Roles[role] or Config.Accounts.Roles.member
        local inserted = B.DB.update([[
            INSERT INTO codex_bank_account_members (account_id, citizenid, role, daily_limit)
            VALUES (?, ?, ?, ?)
        ]], { id, options.memberCid, role, math.floor(tonumber(options.memberLimit) or definition.dailyLimit or 0) })
        if inserted < 1 then
            B.DB.update('DELETE FROM codex_bank_accounts WHERE id = ?', { id })
            return nil
        end
    end
    return tonumber(id), accountNo
end

local function chargeOpeningFee(source, bankId, amount, initialImport)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local bank = Config.Banks[bankId]
    if not player or not cid or not bank then return false, 'not_authenticated' end

    if initialImport then
        local current = B.GetMoney(player, 'bank')
        if current < amount then return false, 'opening_fee' end
        return true
    end

    local account = B.DB.single([[
        SELECT * FROM codex_bank_accounts
        WHERE owner_cid = ? AND account_type = 'checking'
        ORDER BY id ASC LIMIT 1
    ]], { cid })
    if not account or tonumber(account.balance) < amount then
        return false, 'opening_fee'
    end
    local accountId = tonumber(account.id)
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { amount, accountId, amount }),
        vaultQuery(bankId, amount),
        transactionLog(accountId, nil, cid, 'account_fee', amount, 0, 'Account opening fee')
    }
    if not B.DB.transaction(safeQueries(queries)) then
        return false, 'server_error'
    end
    return true
end

local function ensureChecking(source, bankId)
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local bank = Config.Banks[bankId]
    if not player or not cid or not bank then return nil, 'invalid_bank' end

    local existing = B.DB.single([[
        SELECT * FROM codex_bank_accounts
        WHERE owner_cid = ? AND bank_id = ? AND account_type = 'checking'
        LIMIT 1
    ]], { cid, bankId })
    if existing then return existing end

    B.ReconcileLegacy(source)
    local sync = B.DB.single('SELECT last_bank_balance FROM codex_bank_legacy_sync WHERE citizenid = ?', { cid })
    local initialImport = sync == nil and Config.LegacySync and Config.LegacySync.Enabled ~= false
    local openingFee = math.max(0, math.floor(tonumber(bank.openingFee) or 0))
    if not initialImport and openingFee > 0 then
        local primary = B.DB.single("SELECT id FROM codex_bank_accounts WHERE owner_cid = ? AND account_type = 'checking' ORDER BY id ASC LIMIT 1", { cid })
        if not primary then openingFee = 0 end
    end
    local legacyBalance = initialImport and B.GetMoney(player, 'bank') or 0
    if initialImport and legacyBalance < openingFee then
        return nil, 'opening_fee'
    end

    if not initialImport then
        local paid, why = chargeOpeningFee(source, bankId, openingFee, false)
        if not paid then return nil, why end
    end

    local balance = initialImport and (legacyBalance - openingFee) or 0
    local id, accountNo = createAccount(bankId, 'checking', bank.label .. ' — Personal Checking', cid, nil, balance, {
        memberCid = cid,
        role = 'owner',
        dailyLimit = bank.defaultDailyLimit,
        maxBalance = bank.maxBalance,
        memberLimit = Config.Accounts.Roles.owner.dailyLimit
    })
    if not id then
        if not initialImport and openingFee > 0 then
            local primary = B.DB.single("SELECT id FROM codex_bank_accounts WHERE owner_cid = ? AND account_type = 'checking' ORDER BY id ASC LIMIT 1", { cid })
            if primary then
                B.DB.transaction({
                    queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { openingFee, primary.id }),
                    queryObject('UPDATE codex_bank_vaults SET fee_balance = GREATEST(0, fee_balance - ?) WHERE bank_id = ?', { openingFee, bankId }),
                    transactionLog(nil, primary.id, cid, 'account_fee_reversal', openingFee, 0, 'Account opening fee reversal')
                })
                B.SyncLegacy(cid)
            end
        end
        return nil, 'server_error'
    end

    if initialImport then
        local initialQueries = {
            queryObject([[
                INSERT INTO codex_bank_legacy_sync (citizenid, last_bank_balance)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE last_bank_balance = VALUES(last_bank_balance)
            ]], { cid, balance })
        }
        local feeVault = vaultQuery(bankId, openingFee)
        if feeVault then initialQueries[#initialQueries + 1] = feeVault end
        if openingFee > 0 then
            initialQueries[#initialQueries + 1] = transactionLog(id, nil, cid, 'account_fee', openingFee, 0, 'Account opening fee')
        end
        if not B.DB.transaction(safeQueries(initialQueries)) then
            B.DB.update('DELETE FROM codex_bank_account_members WHERE account_id = ? AND citizenid = ?', { id, cid })
            B.DB.update('DELETE FROM codex_bank_accounts WHERE id = ?', { id })
            return nil, 'server_error'
        end
        B.SetLegacyBank(player, balance, 'codex-banking-account-open')
        local currentBank = B.GetMoney(player, 'bank')
        if currentBank ~= balance then
            B.DB.update('UPDATE codex_bank_legacy_sync SET last_bank_balance = ? WHERE citizenid = ?', { currentBank, cid })
        end
    else
        B.SyncLegacy(cid)
    end
    return B.DB.single('SELECT * FROM codex_bank_accounts WHERE id = ?', { id }) or { id = id, account_no = accountNo, bank_id = bankId, account_type = 'checking', label = bank.label, balance = balance }
end

local function accountWrite(source, accountId, amount, permission, kind, description, fee, extraQueries)
    local account, err, player, cid = getAccount(source, accountId)
    if not account then return nil, err end
    fee = math.floor(tonumber(fee) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local total = amount + fee
    local allowed, why = canSpend(account, cid, total, permission)
    if not allowed then return nil, why end
    local newBalance = account.balance - total
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { total, account.id, total }),
        memberSpendQuery(account.id, cid, total),
        accountUsageQuery(account.id, cid, total),
        transactionLog(account.id, nil, cid, kind, amount, fee, description)
    }
    if extraQueries then
        for _, query in ipairs(extraQueries) do queries[#queries + 1] = query end
    end
    if not B.DB.transaction(safeQueries(queries)) then return nil, 'server_error' end
    if account.owner_cid and (account.account_type == 'checking' or account.account_type == 'savings') then
        B.SyncLegacy(account.owner_cid)
    end
    return { account = account, player = player, citizenid = cid, newBalance = newBalance }
end

local function transfer(source, sourceAccountId, destinationAccount, amount, description, kind, extraQueries, feeOverride)
    local sourceAccount, err, player, cid = getAccount(source, sourceAccountId)
    if not sourceAccount then return nil, err end
    if not destinationAccount then return nil, 'account_not_found' end
    local destinationId = tonumber(destinationAccount.id)
    if not destinationId or destinationId == tonumber(sourceAccount.id) then return nil, 'invalid_destination' end

    amount = math.floor(tonumber(amount) or 0)
    if amount < Config.Transfer.MinAmount or amount > Config.Transfer.MaxAmount then return nil, 'invalid_amount' end
    local fee
    if feeOverride ~= nil then
        fee = math.max(0, math.floor(tonumber(feeOverride) or 0))
    elseif sourceAccount.bank_id ~= destinationAccount.bank_id then
        local maxRate = math.max(0, tonumber(Config.Admin.MaxRuntimeTransferFeePercent) or 5.0) / 100
        local rate = math.max(0, math.min(maxRate, tonumber(B.Settings.interBankFeePercent) or tonumber(Config.Transfer.InterBankFeePercent) or 0))
        fee = math.floor(amount * rate)
    else
        local rate = math.max(0, math.min(1, tonumber(Config.Transfer.SameBankFeePercent) or 0))
        fee = math.floor(amount * rate)
    end

    local total = amount + fee
    local allowed, why = canSpend(sourceAccount, cid, total, 'transfer')
    if not allowed then return nil, why end
    local isInterBank = sourceAccount.bank_id ~= destinationAccount.bank_id
    if isInterBank then
        local alreadySent = tonumber(B.DB.scalar([[
            SELECT amount FROM codex_bank_daily_usage
            WHERE citizenid = ? AND usage_type = 'inter_bank_transfer' AND usage_day = CURDATE()
        ]], { cid })) or 0
        if alreadySent + amount > (tonumber(Config.Transfer.InterBankDailyCap) or 5000000) then
            return nil, 'interbank_daily_cap'
        end
    end
    local destBalance = math.floor(tonumber(destinationAccount.balance) or 0)
    local destMax = math.floor(tonumber(destinationAccount.max_balance) or Config.Accounts.DefaultMaxBalance)
    if destMax > 0 and destBalance + amount > destMax then return nil, 'destination_limit' end

    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { total, sourceAccount.id, total }),
        queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', { amount, destinationId, amount }),
        memberSpendQuery(sourceAccount.id, cid, total),
        accountUsageQuery(sourceAccount.id, cid, total),
        transactionLog(sourceAccount.id, destinationId, cid, kind or 'transfer', amount, fee, description or 'Account transfer')
    }
    if isInterBank then
        queries[#queries + 1] = queryObject([[
            INSERT INTO codex_bank_daily_usage (citizenid, usage_type, usage_day, amount)
            VALUES (?, 'inter_bank_transfer', CURDATE(), ?)
            ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
        ]], { cid, amount })
    end
    if fee > 0 then
        local governmentShare = math.max(0, math.min(1, tonumber(Config.Transfer.FeeGovernmentSharePercent) or 1.0))
        local feeToVault = math.floor(fee * governmentShare)
        local vault = vaultQuery(sourceAccount.bank_id, feeToVault)
        if vault then queries[#queries + 1] = vault end
    end
    if extraQueries then
        for _, query in ipairs(extraQueries) do queries[#queries + 1] = query end
    end
    if not B.DB.transaction(safeQueries(queries)) then return nil, 'server_error' end

    if sourceAccount.owner_cid and (sourceAccount.account_type == 'checking' or sourceAccount.account_type == 'savings') then
        B.SyncLegacy(sourceAccount.owner_cid)
    end
    if destinationAccount.owner_cid and (destinationAccount.account_type == 'checking' or destinationAccount.account_type == 'savings') then
        B.SyncLegacy(destinationAccount.owner_cid)
    end
    return { fee = fee, source = sourceAccount, destination = destinationAccount, player = player, citizenid = cid }
end

local function requireBranch(session)
    return branchRequired(session) and session.bankId and Config.Banks[session.bankId]
end

local function requireBankingSession(source, token)
    local session = B.SessionFor(source, token)
    if not session then return nil, 'session_expired' end
    if session.mode ~= 'branch' and session.mode ~= 'atm' and session.mode ~= 'atm_pending' then
        return nil, 'session_expired'
    end
    return session
end

local function accessToOwnChecking(source, accountId)
    local account, err, player, cid = getAccount(source, accountId)
    if not account then return nil, err end
    if account.account_type ~= 'checking' or account.owner_cid ~= cid then
        return nil, 'personal_checking_required'
    end
    return account, nil, player, cid
end

local function expireTimestamp(days)
    return os.date('%Y-%m-%d %H:%M:%S', os.time() + math.floor((tonumber(days) or 1) * 86400))
end

local function isKnownCitizen(citizenid)
    if type(citizenid) ~= 'string' or #citizenid < 2 or #citizenid > 64 then return false end
    if B.GetPlayerByCitizenId(citizenid) then return true end
    return B.DB.single('SELECT citizenid FROM players WHERE citizenid = ? LIMIT 1', { citizenid }) ~= nil
end

local function checkCardSession(source, session, accountId)
    if session.mode ~= 'atm' or not session.cardId then return nil, 'card_required' end
    local card = B.DB.single('SELECT id, account_id, holder_cid, tier, is_frozen, daily_limit, daily_spent, daily_spent_date FROM codex_bank_cards WHERE id = ? AND holder_cid = ?', { session.cardId, B.GetCitizenId(B.GetPlayer(source)) })
    if not card or tonumber(card.account_id) ~= tonumber(accountId) then return nil, 'card_required' end
    if tonumber(card.is_frozen) == 1 then return nil, 'card_frozen' end
    return card
end

local function atmFee(account, amount, session)
    local bank = Config.Banks[account.bank_id] or {}
    local base = math.max(0, math.floor(tonumber(bank.atmFee) or 0))
    local owner = session.atmId and B.DB.single('SELECT owner_cid, surcharge_percent FROM codex_bank_atm_owners WHERE atm_id = ?', { session.atmId })
    local maxSurcharge = math.max(0, tonumber(Config.ATMs.OwnerSurchargeMaxPercent) or 0)
    local surchargePercent = owner and math.max(0, math.min(maxSurcharge, tonumber(owner.surcharge_percent) or 0)) or 0
    local surcharge = math.floor(amount * surchargePercent / 100)
    return base, surcharge, owner
end

local function enforceCardDaily(card, amount)
    local spent = B.DB.scalar([[
        SELECT CASE WHEN daily_spent_date = CURDATE() THEN daily_spent ELSE 0 END
        FROM codex_bank_cards WHERE id = ?
    ]], { card.id })
    spent = math.max(0, tonumber(spent) or 0)
    if spent + amount > (tonumber(card.daily_limit) or 0) then return false end
    return true
end

local function recordCardSpendQuery(cardId, amount)
    return queryObject([[
        UPDATE codex_bank_cards
        SET daily_spent = IF(daily_spent_date = CURDATE(), daily_spent + ?, ?),
            daily_spent_date = CURDATE()
        WHERE id = ?
    ]], { amount, amount, cardId })
end

local function refreshResult(source, session, result)
    if result and result.ok and result.refresh ~= false then
        result.data = B.GetDashboard(source, session)
    end
    return result
end

-- A visit to a real branch creates that network's checking account if needed.
-- The first account imports the player's existing QBCore bank money; later
-- network accounts start at zero and share the same legacy bank aggregate.
QBCore.Functions.CreateCallback('codex_banking:server:openBranch', function(source, cb, bankId)
    if not B.Ready then cb(failure('not_ready')) return end
    if type(bankId) ~= 'string' or not Config.Banks[bankId] then cb(failure('invalid_bank')) return end
    local branch = B.NearestBranch(source, bankId)
    if not branch then cb(failure('too_far')) return end

    local response = B.WithLock(function()
        local liveBranch = B.NearestBranch(source, bankId)
        if not liveBranch or liveBranch.id ~= branch.id then return failure('too_far') end
        local player = B.GetPlayer(source)
        local cid = B.GetCitizenId(player)
        if not cid then return failure('not_authenticated') end
        B.ReconcileLegacy(source)
        local account, err = ensureChecking(source, bankId)
        if not account then return failure(err or 'server_error') end
        local session = B.NewSession(source, 'branch', { bankId = bankId, branchId = branch.id })
        return success('welcome', { token = session.token, data = B.GetDashboard(source, session) })
    end)
    cb(response)
end)

QBCore.Functions.CreateCallback('codex_banking:server:openATM', function(source, cb)
    if not B.Ready then cb(failure('not_ready')) return end
    local atmId = B.NearestATM(source)
    if not atmId then cb(failure('too_far')) return end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    if not cid then cb(failure('not_authenticated')) return end

    local session = B.NewSession(source, 'atm_pending', { atmId = atmId })
    local cards = B.GetCards(cid)
    local ownerRow = B.DB.single('SELECT owner_cid, surcharge_percent, fee_balance FROM codex_bank_atm_owners WHERE atm_id = ?', { atmId })
    local atm = { isOwned = ownerRow ~= nil, isOwner = ownerRow ~= nil and ownerRow.owner_cid == cid, price = tonumber(Config.ATMs.BasePrice) or 250000 }
    if atm.isOwner then
        atm.surcharge_percent = tonumber(ownerRow.surcharge_percent) or 0
        atm.fee_balance = tonumber(ownerRow.fee_balance) or 0
    end
    cb(success('insert_card', { token = session.token, atmId = atmId, cards = cards, atm = atm }))
end)

QBCore.Functions.CreateCallback('codex_banking:server:openAdmin', function(source, cb)
    if not B.Ready then cb(failure('not_ready')) return end
    if not B.IsAdmin(source) then cb(failure('no_permission')) return end
    local session = B.NewSession(source, 'admin', {})
    local dashboard = B.GetDashboard(source, session)
    cb(success('welcome', { token = session.token, data = dashboard }))
end)

local function openNewChecking(source, payload, session)
    if not requireBranch(session) then return failure('branch_only') end
    local bankId = tostring(payload.bankId or session.bankId)
    if bankId ~= session.bankId then return failure('branch_only') end
    local exists = B.DB.single([[
        SELECT id FROM codex_bank_accounts
        WHERE owner_cid = ? AND bank_id = ? AND account_type = 'checking' LIMIT 1
    ]], { B.GetCitizenId(B.GetPlayer(source)), bankId })
    if exists then return failure('account_exists') end
    local account, err = ensureChecking(source, bankId)
    if not account then return failure(err or 'server_error') end
    return success('account_opened')
end

local function openSavings(source, payload, session)
    if not requireBranch(session) then return failure('branch_only') end
    if not Config.Savings.Enabled then return failure('feature_disabled') end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local tierId = B.Number(payload.tier, 1, 4)
    local tier = tierId and Config.Savings.Tiers[tierId]
    if not tier then return failure('invalid_tier') end
    local exists = B.DB.single([[
        SELECT id FROM codex_bank_accounts
        WHERE owner_cid = ? AND bank_id = ? AND account_type = 'savings' LIMIT 1
    ]], { cid, session.bankId })
    if exists then return failure('account_exists') end

    local checking = B.DB.single([[
        SELECT * FROM codex_bank_accounts
        WHERE owner_cid = ? AND bank_id = ? AND account_type = 'checking' LIMIT 1
    ]], { cid, session.bankId })
    if not checking then
        local opened, err = ensureChecking(source, session.bankId)
        if not opened then return failure(err or 'account_required') end
        checking = opened
    end
    local cost = math.max(0, math.floor(tonumber(tier.openingFee) or 0))
    if cost > 0 and tonumber(checking.balance) < cost then return failure('insufficient_funds') end

    if cost > 0 then
        local queries = {
            queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { cost, checking.id, cost }),
            vaultQuery(session.bankId, cost),
            transactionLog(checking.id, nil, cid, 'savings_open_fee', cost, 0, 'Savings account opening fee')
        }
        if not B.DB.transaction(safeQueries(queries)) then return failure('server_error') end
    end

    local bank = Config.Banks[session.bankId]
    local id = createAccount(session.bankId, 'savings', tier.label .. ' — Savings Account', cid, nil, 0, {
        memberCid = cid,
        role = 'owner',
        memberLimit = Config.Accounts.Roles.owner.dailyLimit,
        dailyLimit = bank.defaultDailyLimit,
        maxBalance = bank.maxBalance,
        savingsTier = tierId
    })
    if not id then
        if cost > 0 then
            B.DB.transaction({
                queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { cost, checking.id }),
                queryObject('UPDATE codex_bank_vaults SET fee_balance = GREATEST(0, fee_balance - ?) WHERE bank_id = ?', { cost, session.bankId }),
                transactionLog(nil, checking.id, cid, 'savings_fee_reversal', cost, 0, 'Savings opening fee reversal')
            })
            B.SyncLegacy(cid)
        end
        return failure('server_error')
    end
    B.SyncLegacy(cid)
    return success('savings_opened')
end

local function createSharedAccount(source, payload, session)
    if not requireBranch(session) then return failure('branch_only') end
    local label = B.Trim(payload.label or '', 48)
    if #label < 3 then return failure('invalid_label') end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local count = tonumber(B.DB.scalar([[
        SELECT COUNT(*) FROM codex_bank_account_members m
        JOIN codex_bank_accounts a ON a.id = m.account_id
        WHERE m.citizenid = ? AND m.role = 'owner' AND a.account_type = 'shared'
    ]], { cid })) or 0
    if count >= Config.Accounts.MaxSharedAccounts then return failure('account_limit') end

    local bank = Config.Banks[session.bankId]
    local id = createAccount(session.bankId, 'shared', label, nil, nil, 0, {
        memberCid = cid,
        role = 'owner',
        memberLimit = Config.Accounts.Roles.owner.dailyLimit,
        dailyLimit = bank.defaultDailyLimit,
        maxBalance = bank.maxBalance
    })
    if not id then return failure('server_error') end
    return success('shared_opened')
end

local function addSharedMember(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if account.account_type ~= 'shared' or not account.canManage then return failure('no_permission') end
    local targetCid = B.Trim(payload.citizenid or '', 64)
    if not isKnownCitizen(targetCid) then return failure('citizen_not_found') end
    if targetCid == cid then return failure('already_member') end
    local role = tostring(payload.role or 'member')
    if role ~= 'admin' and role ~= 'member' and role ~= 'viewer' then return failure('invalid_role') end
    local existing = B.DB.single('SELECT role FROM codex_bank_account_members WHERE account_id = ? AND citizenid = ?', { account.id, targetCid })
    if existing then return failure('already_member') end
    local memberCount = tonumber(B.DB.scalar('SELECT COUNT(*) FROM codex_bank_account_members WHERE account_id = ?', { account.id })) or 0
    if memberCount >= (tonumber(Config.Accounts.MaxSharedMembers) or 4) then return failure('member_limit') end
    local definition = Config.Accounts.Roles[role]
    local inserted = B.DB.update('INSERT INTO codex_bank_account_members (account_id, citizenid, role, daily_limit) VALUES (?, ?, ?, ?)', {
        account.id, targetCid, role, tonumber(definition.dailyLimit) or 0
    })
    if inserted < 1 then return failure('server_error') end
    return success('member_added')
end

local function removeSharedMember(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if account.account_type ~= 'shared' or not account.canManage then return failure('no_permission') end
    local targetCid = B.Trim(payload.citizenid or '', 64)
    if targetCid == cid then return failure('cannot_remove_self') end
    local result = B.DB.update('DELETE FROM codex_bank_account_members WHERE account_id = ? AND citizenid = ? AND role <> \'owner\'', { account.id, targetCid })
    if result < 1 then return failure('member_not_found') end
    B.DB.update('DELETE FROM codex_bank_cards WHERE account_id = ? AND holder_cid = ?', { account.id, targetCid })
    return success('member_removed')
end

local function upgradeAccount(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if not account.canManage or account.account_type == 'company' then return failure('no_permission') end
    local nextLevel = (tonumber(account.account_level) or 1) + 1
    local upgrade = Config.Accounts.UpgradeLevels[nextLevel]
    if not upgrade then return failure('max_level') end
    local cost = math.max(0, math.floor(tonumber(upgrade.price) or 0))
    if account.balance < cost then return failure('insufficient_funds') end
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ?, account_level = ?, daily_limit = ?, max_balance = ? WHERE id = ? AND balance >= ?', {
            cost, nextLevel, upgrade.dailyLimit, upgrade.maxBalance, account.id, cost
        })
    }
    local feeVault = vaultQuery(account.bank_id, cost)
    if feeVault then queries[#queries + 1] = feeVault end
    queries[#queries + 1] = transactionLog(account.id, nil, cid, 'account_upgrade', cost, 0, ('Account level %d'):format(nextLevel))
    if not B.DB.transaction(safeQueries(queries)) then return failure('server_error') end
    if account.owner_cid then B.SyncLegacy(account.owner_cid) end
    return success('account_upgraded')
end

local function setSavingsGoal(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if account.account_type ~= 'savings' or not account.canManage then return failure('no_permission') end
    local goal = B.Number(payload.amount, 0, Config.Security.MaxAmount)
    if not goal then return failure('invalid_amount') end
    local label = B.Trim(payload.label or '', 64)
    B.DB.update('UPDATE codex_bank_accounts SET savings_goal = ?, savings_goal_label = ? WHERE id = ?', { goal, label, account.id })
    local saved = B.DB.single('SELECT savings_goal, savings_goal_label FROM codex_bank_accounts WHERE id = ?', { account.id })
    if not saved or tonumber(saved.savings_goal) ~= goal or tostring(saved.savings_goal_label or '') ~= label then return failure('server_error') end
    return success('goal_saved')
end

local function createCard(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if not account.canManage then return failure('no_permission') end
    local tierId = tostring(payload.tier or 'standard')
    local tier = Config.Cards.Tiers[tierId]
    if not tier then return failure('invalid_tier') end
    local pin = tostring(payload.pin or '')
    if not pin:match('^%d%d%d%d$') then return failure('invalid_pin') end
    local count = tonumber(B.DB.scalar('SELECT COUNT(*) FROM codex_bank_cards WHERE holder_cid = ?', { cid })) or 0
    if count >= Config.Cards.MaxPerCitizen then return failure('card_limit') end
    local cost = math.max(0, math.floor(tonumber(tier.issueCost) or 0))
    if account.balance < cost then return failure('insufficient_funds') end

    local last4 = ('%04d'):format(math.random(0, 9999))
    local cardId = B.DB.insert([[
        INSERT INTO codex_bank_cards (account_id, holder_cid, tier, last4, pin_digest, daily_limit)
        VALUES (?, ?, ?, ?, '--------', ?)
    ]], { account.id, cid, tierId, last4, tonumber(tier.dailyLimit) or 0 })
    if not cardId then return failure('server_error') end
    local digest = B.PinDigest(cid, cardId, pin)
    if type(digest) ~= 'string' or #digest ~= 64 or B.DB.update('UPDATE codex_bank_cards SET pin_digest = ? WHERE id = ?', { digest, cardId }) < 1 then
        B.DB.update('DELETE FROM codex_bank_cards WHERE id = ?', { cardId })
        return failure('server_error')
    end

    if cost > 0 then
        local queries = {
            queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { cost, account.id, cost }),
            vaultQuery(account.bank_id, cost),
            transactionLog(account.id, nil, cid, 'card_issue', cost, 0, tier.label .. ' card issue fee')
        }
        if not B.DB.transaction(safeQueries(queries)) then
            B.DB.update('DELETE FROM codex_bank_cards WHERE id = ?', { cardId })
            return failure('server_error')
        end
    end
    if account.owner_cid then B.SyncLegacy(account.owner_cid) end
    return success('card_created')
end

local function freezeCard(source, payload)
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local cardId = B.Number(payload.cardId, 1, 2147483647)
    if not cardId then return failure('card_not_found') end
    local card = B.DB.single('SELECT id, holder_cid FROM codex_bank_cards WHERE id = ?', { cardId })
    if not card or card.holder_cid ~= cid then return failure('card_not_found') end
    local frozen = payload.frozen == true or payload.frozen == 1 or payload.frozen == '1'
    B.DB.update('UPDATE codex_bank_cards SET is_frozen = ? WHERE id = ?', { frozen and 1 or 0, cardId })
    local current = B.DB.scalar('SELECT is_frozen FROM codex_bank_cards WHERE id = ?', { cardId })
    if tonumber(current) ~= (frozen and 1 or 0) then return failure('server_error') end
    if frozen and B.Sessions[source] and B.Sessions[source].cardId == cardId then
        B.Sessions[source] = nil
    end
    return success(frozen and 'card_frozen' or 'card_unfrozen')
end

local function unlockCard(source, payload, session)
    if session.mode ~= 'atm_pending' then return failure('session_expired') end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local cardId = B.Number(payload.cardId, 1, 2147483647)
    local pin = tostring(payload.pin or '')
    if not cardId or not pin:match('^%d%d%d%d$') then return failure('invalid_pin') end
    local card = B.DB.single('SELECT * FROM codex_bank_cards WHERE id = ? AND holder_cid = ? LIMIT 1', { cardId, cid })
    if not card then return failure('card_not_found') end
    if tonumber(card.is_frozen) == 1 then return failure('card_frozen') end
    local locked = card.locked_until and tostring(card.locked_until) or nil
    if locked and locked > os.date('%Y-%m-%d %H:%M:%S') then return failure('card_locked') end

    local supplied = B.PinDigest(cid, cardId, pin)
    if type(supplied) ~= 'string' or #supplied ~= 64 then return failure('server_error') end
    if supplied ~= tostring(card.pin_digest) then
        local attempts = math.min(tonumber(card.failed_attempts) or 0, 10) + 1
        -- Use a fixed seconds interval, not a client-supplied value.
        if attempts >= Config.Security.MaxCardPinAttempts then
            local lockedUntil = os.date('%Y-%m-%d %H:%M:%S', os.time() + Config.Security.CardLockSeconds)
            B.DB.update('UPDATE codex_bank_cards SET failed_attempts = ?, locked_until = ? WHERE id = ?', { attempts, lockedUntil, cardId })
        else
            B.DB.update('UPDATE codex_bank_cards SET failed_attempts = ? WHERE id = ?', { attempts, cardId })
        end
        return failure(attempts >= Config.Security.MaxCardPinAttempts and 'card_locked' or 'wrong_pin')
    end

    B.DB.update('UPDATE codex_bank_cards SET failed_attempts = 0, locked_until = NULL WHERE id = ?', { cardId })
    session.mode = 'atm'
    session.cardId = cardId
    session.expiresAt = os.time() + Config.Security.SessionSeconds
    return success('card_accepted', { data = B.GetDashboard(source, session) })
end

local function deposit(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local account, err, player, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    local amount = B.Number(payload.amount, Config.Transfer.MinAmount, math.min(Config.Security.MaxAmount, account.max_balance))
    if not amount then return failure('invalid_amount') end
    if account.balance + amount > account.max_balance then return failure('destination_limit') end
    if not player.Functions.RemoveMoney('cash', amount, 'codex-bank-deposit') then return failure('insufficient_cash') end

    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', { amount, account.id, amount }),
        transactionLog(nil, account.id, cid, 'deposit', amount, 0, 'Cash deposit')
    }
    if not B.DB.transaction(queries) then
        player.Functions.AddMoney('cash', amount, 'codex-bank-deposit-refund')
        return failure('server_error')
    end
    if account.owner_cid and (account.account_type == 'checking' or account.account_type == 'savings') then B.SyncLegacy(account.owner_cid) end
    return success('deposit_complete')
end

local function withdraw(source, payload, session)
    if not branchRequired(session) and not atmRequired(session) then return failure('session_expired') end
    local account, err, player, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    local amount = B.Number(payload.amount, Config.Transfer.MinAmount, math.min(Config.Security.MaxAmount, account.max_balance))
    if not amount then return failure('invalid_amount') end
    local card
    local fee = 0
    local surcharge = 0
    local atmOwner
    if atmRequired(session) then
        card, err = checkCardSession(source, session, account.id)
        if not card then return failure(err) end
        local baseFee
        baseFee, surcharge, atmOwner = atmFee(account, amount, session)
        fee = baseFee + surcharge
        if not enforceCardDaily(card, amount) then return failure('card_daily_limit') end
    else
        fee = math.max(0, math.floor(tonumber((Config.Banks[session.bankId] or {}).branchWithdrawFee) or 0))
    end

    local total = amount + fee
    local allowed, why = canSpend(account, cid, total, 'withdraw')
    if not allowed then return failure(why) end
    local ownerShare = 0
    if atmOwner and atmOwner.owner_cid then
        local base = math.max(0, fee - surcharge)
        local sharePercent = math.max(0, math.min(1, tonumber(Config.ATMs.OwnerFeeShare) or 0.5))
        ownerShare = math.min(fee, math.floor(base * sharePercent) + surcharge)
    end
    local vaultAmount = math.max(0, fee - ownerShare)
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { total, account.id, total }),
        memberSpendQuery(account.id, cid, total),
        accountUsageQuery(account.id, cid, total),
        transactionLog(account.id, nil, cid, atmRequired(session) and 'atm_withdraw' or 'withdraw', amount, fee, atmRequired(session) and 'ATM cash withdrawal' or 'Branch cash withdrawal')
    }
    if card then queries[#queries + 1] = recordCardSpendQuery(card.id, amount) end
    local vault = vaultQuery(account.bank_id, vaultAmount)
    if vault then queries[#queries + 1] = vault end
    if ownerShare > 0 and session.atmId then
        queries[#queries + 1] = queryObject('UPDATE codex_bank_atm_owners SET fee_balance = fee_balance + ? WHERE atm_id = ?', { ownerShare, session.atmId })
    end
    if not B.DB.transaction(safeQueries(queries)) then return failure('server_error') end
    local cashAdded = player.Functions.AddMoney('cash', amount, 'codex-bank-withdraw')
    if cashAdded == false then
        local reversals = {
            queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { total, account.id }),
            queryObject('UPDATE codex_bank_account_members SET daily_spent = GREATEST(0, daily_spent - ?) WHERE account_id = ? AND citizenid = ? AND daily_spent_date = CURDATE()', { total, account.id, cid }),
            queryObject('UPDATE codex_bank_daily_usage SET amount = GREATEST(0, amount - ?) WHERE citizenid = ? AND usage_type = ? AND usage_day = CURDATE()', { total, cid, ('account_%s'):format(tostring(account.id)) }),
            queryObject('UPDATE codex_bank_vaults SET fee_balance = GREATEST(0, fee_balance - ?) WHERE bank_id = ?', { vaultAmount, account.bank_id })
        }
        if card then
            reversals[#reversals + 1] = queryObject('UPDATE codex_bank_cards SET daily_spent = GREATEST(0, daily_spent - ?) WHERE id = ? AND daily_spent_date = CURDATE()', { amount, card.id })
        end
        if ownerShare > 0 and session.atmId then
            reversals[#reversals + 1] = queryObject('UPDATE codex_bank_atm_owners SET fee_balance = GREATEST(0, fee_balance - ?) WHERE atm_id = ?', { ownerShare, session.atmId })
        end
        reversals[#reversals + 1] = transactionLog(nil, account.id, cid, 'withdraw_reversal', amount, fee, 'Cash payout failed; reversal')
        B.DB.transaction(reversals)
        return failure('server_error')
    end
    if account.owner_cid and (account.account_type == 'checking' or account.account_type == 'savings') then B.SyncLegacy(account.owner_cid) end
    return success('withdraw_complete')
end

local function sendTransfer(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local target = B.Trim(payload.destination or payload.accountNo or '', 32):gsub('%s+', ''):upper()
    if #target < 4 then return failure('invalid_destination') end
    local destination = B.DB.single('SELECT * FROM codex_bank_accounts WHERE UPPER(account_no) = ? LIMIT 1', { target })
    if not destination then return failure('account_not_found') end
    local amount = B.Number(payload.amount, Config.Transfer.MinAmount, Config.Transfer.MaxAmount)
    if not amount then return failure('invalid_amount') end
    local description = B.Trim(payload.description or '', 100)
    local result, err = transfer(source, payload.accountId, destination, amount, description ~= '' and description or 'Account transfer', 'transfer')
    if not result then return failure(err) end
    return success('transfer_complete', { fee = result.fee })
end

local function setCardFreeze(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    return freezeCard(source, payload)
end

local function newInvoice(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    if not Config.Invoices.Enabled then return failure('feature_disabled') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if not account.canManage then return failure('no_permission') end
    local recipientCid = B.Trim(payload.recipientCid or '', 64)
    if recipientCid == cid or not isKnownCitizen(recipientCid) then return failure('citizen_not_found') end
    local amount = B.Number(payload.amount, 1, Config.Invoices.MaxAmount)
    if not amount then return failure('invalid_amount') end
    local reason = B.Trim(payload.reason or '', Config.Invoices.MaxReasonLength)
    if reason == '' then return failure('invalid_reason') end
    local reference = B.MakeReference('INV')
    local id = B.DB.insert([[
        INSERT INTO codex_bank_invoices
            (reference, issuer_cid, recipient_cid, issuer_account_id, amount, reason, due_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { reference, cid, recipientCid, account.id, amount, reason, expireTimestamp(Config.Invoices.ExpiryDays) })
    if not id then return failure('server_error') end
    local recipient = B.GetPlayerByCitizenId(recipientCid)
    if recipient then B.Notify(recipient.PlayerData.source, 'invoice_received', 'primary') end
    return success('invoice_created')
end

local function payInvoice(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local invoiceId = B.Number(payload.invoiceId, 1, 2147483647)
    if not invoiceId then return failure('invoice_not_found') end
    local invoice = B.DB.single('SELECT * FROM codex_bank_invoices WHERE id = ? AND recipient_cid = ? AND status = \'pending\' LIMIT 1', { invoiceId, cid })
    if not invoice then return failure('invoice_not_found') end
    if tostring(invoice.due_at) < os.date('%Y-%m-%d %H:%M:%S') then
        B.DB.update('UPDATE codex_bank_invoices SET status = \'expired\' WHERE id = ? AND status = \'pending\'', { invoiceId })
        return failure('invoice_expired')
    end
    local destination = B.DB.single('SELECT * FROM codex_bank_accounts WHERE id = ? LIMIT 1', { invoice.issuer_account_id })
    if not destination then return failure('account_not_found') end
    local extra = { queryObject("UPDATE codex_bank_invoices SET status = 'paid', paid_at = NOW() WHERE id = ? AND status = 'pending'", { invoiceId }) }
    local result, err = transfer(source, payload.accountId, destination, tonumber(invoice.amount), 'Invoice ' .. tostring(invoice.reference), 'invoice_payment', extra)
    if not result then return failure(err) end
    return success('invoice_paid')
end

local function issueCheque(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    if not Config.Cheques.Enabled then return failure('feature_disabled') end
    local account, err, _, cid = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if not account.canWithdraw then return failure('no_permission') end
    local amount = B.Number(payload.amount, 1, Config.Cheques.MaxAmount)
    if not amount then return failure('invalid_amount') end
    if amount > account.balance then return failure('insufficient_funds') end
    local beneficiary = B.Trim(payload.beneficiaryCid or '', 64)
    if beneficiary ~= '' and not isKnownCitizen(beneficiary) then return failure('citizen_not_found') end
    local reason = B.Trim(payload.reason or '', 100)
    local chequeNo = ('%08d%04d'):format(os.time() % 100000000, math.random(0, 9999))
    local beneficiarySql = beneficiary ~= '' and '?' or 'NULL'
    local values = { chequeNo, cid, account.id }
    if beneficiary ~= '' then values[#values + 1] = beneficiary end
    values[#values + 1] = amount
    values[#values + 1] = reason
    values[#values + 1] = expireTimestamp(Config.Cheques.ExpiryDays)
    local id = B.DB.insert(([[
        INSERT INTO codex_bank_cheques
            (cheque_no, issuer_cid, account_id, beneficiary_cid, amount, reason, expires_at)
        VALUES (?, ?, ?, %s, ?, ?, ?)
    ]]):format(beneficiarySql), values)
    if not id then return failure('server_error') end
    return success('cheque_created', { chequeNo = chequeNo })
end

local function cashCheque(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    if not Config.Cheques.Enabled then return failure('feature_disabled') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local chequeNo = B.Trim(payload.chequeNo or '', 16):gsub('%s+', ''):upper()
    if #chequeNo < 8 then return failure('cheque_not_found') end
    local cheque = B.DB.single('SELECT * FROM codex_bank_cheques WHERE cheque_no = ? AND status = \'issued\' LIMIT 1', { chequeNo })
    if not cheque then return failure('cheque_not_found') end
    if cheque.beneficiary_cid and cheque.beneficiary_cid ~= cid then return failure('cheque_not_for_you') end
    if tostring(cheque.expires_at) < os.date('%Y-%m-%d %H:%M:%S') then
        B.DB.update('UPDATE codex_bank_cheques SET status = \'expired\' WHERE id = ? AND status = \'issued\'', { cheque.id })
        return failure('cheque_expired')
    end

    local issuer = B.DB.single('SELECT * FROM codex_bank_accounts WHERE id = ? LIMIT 1', { cheque.account_id })
    if not issuer then return failure('account_not_found') end
    local amount = tonumber(cheque.amount) or 0
    if tonumber(issuer.balance) < amount then
        B.DB.update('UPDATE codex_bank_cheques SET status = \'bounced\' WHERE id = ? AND status = \'issued\'', { cheque.id })
        return failure('cheque_bounced')
    end

    local destinationId = tonumber(payload.accountId)
    local destination
    if destinationId and destinationId > 0 then
        local err
        destination, err = getAccount(source, destinationId)
        if not destination then return failure(err) end
        if destination.owner_cid ~= cid or not (destination.account_type == 'checking' or destination.account_type == 'savings') then return failure('personal_account_required') end
        if destination.balance + amount > destination.max_balance then return failure('destination_limit') end
    end

    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { amount, issuer.id, amount }),
        queryObject("UPDATE codex_bank_cheques SET status = 'cashed', cashed_by = ?, cashed_at = NOW() WHERE id = ? AND status = 'issued'", { cid, cheque.id }),
        transactionLog(issuer.id, destination and destination.id or nil, cid, 'cheque_cash', amount, 0, 'Cheque ' .. chequeNo)
    }
    if destination then
        queries[#queries + 1] = queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', { amount, destination.id, amount })
    end
    if not B.DB.transaction(queries) then return failure('server_error') end

    if destination then
        if issuer.owner_cid then B.SyncLegacy(issuer.owner_cid) end
        if destination.owner_cid then B.SyncLegacy(destination.owner_cid) end
    else
        local player = B.GetPlayer(source)
        if not player.Functions.AddMoney('cash', amount, 'codex-bank-cheque') then
            B.DB.transaction({
                queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { amount, issuer.id }),
                queryObject("UPDATE codex_bank_cheques SET status = 'issued', cashed_by = NULL, cashed_at = NULL WHERE id = ?", { cheque.id }),
                transactionLog(nil, issuer.id, cid, 'cheque_reversal', amount, 0, 'Cheque payout failed; reversal')
            })
            return failure('server_error')
        end
        if issuer.owner_cid then B.SyncLegacy(issuer.owner_cid) end
    end
    return success('cheque_cashed')
end

local function cancelCheque(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local chequeId = B.Number(payload.chequeId, 1, 2147483647)
    if not chequeId then return failure('cheque_not_found') end
    local changed = B.DB.update("UPDATE codex_bank_cheques SET status = 'cancelled' WHERE id = ? AND issuer_cid = ? AND status = 'issued'", { chequeId, cid })
    if changed < 1 then return failure('cheque_not_found') end
    return success('cheque_cancelled')
end

local function applyLoan(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    if not Config.Loans.Enabled then return failure('feature_disabled') end
    local player = B.GetPlayer(source)
    local cid = B.GetCitizenId(player)
    local planId = tostring(payload.planId or '')
    local plan = Config.Loans.Plans[planId]
    if not plan then return failure('invalid_loan_plan') end
    local score = B.CreditScore(cid)
    if score < (tonumber(plan.minScore) or 300) then return failure('credit_score_low') end
    local amount = B.Number(payload.amount, 1, math.min(tonumber(plan.maxAmount) or 0, Config.Security.MaxAmount))
    if not amount then return failure('invalid_amount') end
    local active = tonumber(B.DB.scalar("SELECT COUNT(*) FROM codex_bank_loans WHERE borrower_cid = ? AND status IN ('active', 'late', 'defaulted')", { cid })) or 0
    if active >= Config.Loans.MaxActiveLoans then return failure('loan_limit') end

    local account, err = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if account.account_type ~= plan.accountType or (plan.accountType == 'checking' and account.owner_cid ~= cid) then
        return failure('wrong_loan_account')
    end
    if plan.accountType == 'company' and not account.canManage then return failure('no_permission') end

    local collateral = B.Trim(payload.collateralPlate or '', 16):upper()
    if plan.requiresVehicle then
        if collateral == '' then return failure('collateral_required') end
        local vehicleTable = tostring(Config.Loans.VehicleTable or 'player_vehicles')
        if not vehicleTable:match('^[%w_]+$') then return failure('server_error') end
        local vehicle = B.DB.single(('SELECT plate FROM `%s` WHERE citizenid = ? AND UPPER(plate) = ? LIMIT 1'):format(vehicleTable), { cid, collateral })
        if not vehicle then return failure('vehicle_not_owned') end
        local pledged = B.DB.single("SELECT id FROM codex_bank_loans WHERE collateral_plate = ? AND status IN ('active', 'late', 'defaulted') LIMIT 1", { collateral })
        if pledged then return failure('vehicle_pledged') end
    else
        collateral = nil
    end

    local adjustment = 0
    for _, band in ipairs(Config.Loans.CreditBands or {}) do
        if score >= band.min and score <= band.max then adjustment = tonumber(band.rateAdjustment) or 0 break end
    end
    local rate = math.max(0.01, (tonumber(plan.annualRate) or 0.15) + adjustment)
    local termDays = math.max(1, math.floor(tonumber(plan.termDays) or 14))
    local interest = math.floor(amount * rate * (termDays / 365))
    local total = amount + interest
    if account.balance + amount > account.max_balance then return failure('destination_limit') end

    local reference = B.MakeReference('LN')
    local dueAt = expireTimestamp(termDays)
    local collateralSql = collateral ~= nil and '?' or 'NULL'
    local loanValues = { reference, cid, account.id, account.bank_id, planId, amount, total, rate, dueAt }
    if collateral ~= nil then loanValues[#loanValues + 1] = collateral end
    local loanId = B.DB.insert(([[
        INSERT INTO codex_bank_loans
            (reference, borrower_cid, account_id, bank_id, plan_id, principal, balance, interest_rate, due_at, collateral_plate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, %s)
    ]]):format(collateralSql), loanValues)
    if not loanId then return failure('server_error') end

    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', { amount, account.id, amount }),
        transactionLog(nil, account.id, cid, 'loan_disbursement', amount, 0, ('Loan %s'):format(reference))
    }
    if not B.DB.transaction(queries) then
        B.DB.update("UPDATE codex_bank_loans SET status = 'cancelled' WHERE id = ?", { loanId })
        return failure('server_error')
    end
    if account.owner_cid then B.SyncLegacy(account.owner_cid) end
    return success('loan_approved', { reference = reference, dueAt = dueAt })
end

local function payLoan(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local loanId = B.Number(payload.loanId, 1, 2147483647)
    local amount = B.Number(payload.amount, 1, Config.Security.MaxAmount)
    if not loanId or not amount then return failure('invalid_amount') end
    local loan = B.DB.single("SELECT * FROM codex_bank_loans WHERE id = ? AND borrower_cid = ? AND status IN ('active', 'late', 'defaulted') LIMIT 1", { loanId, cid })
    if not loan then return failure('loan_not_found') end
    local balance = math.floor(tonumber(loan.balance) or 0)
    amount = math.min(amount, balance)
    local account, err = getAccount(source, payload.accountId)
    if not account then return failure(err) end
    if account.account_type == 'company' and not account.canWithdraw then return failure('no_permission') end

    local allowed, why = canSpend(account, cid, amount, 'withdraw')
    if not allowed then return failure(why) end
    local remaining = balance - amount
    local status = remaining <= 0 and 'paid' or (loan.status == 'defaulted' and 'defaulted' or (tostring(loan.due_at) < os.date('%Y-%m-%d %H:%M:%S') and 'late' or 'active'))
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { amount, account.id, amount }),
        memberSpendQuery(account.id, cid, amount),
        accountUsageQuery(account.id, cid, amount),
        queryObject('UPDATE codex_bank_loans SET balance = ?, status = ? WHERE id = ? AND balance >= ?', { remaining, status, loanId, amount }),
        transactionLog(account.id, nil, cid, 'loan_payment', amount, 0, 'Loan repayment ' .. tostring(loan.reference))
    }
    if not B.DB.transaction(queries) then return failure('server_error') end
    if account.owner_cid then B.SyncLegacy(account.owner_cid) end
    if remaining <= 0 then
        local paidOnTime = tostring(loan.due_at) >= os.date('%Y-%m-%d %H:%M:%S')
        B.AdjustCredit(cid, paidOnTime and 25 or 5)
    end
    return success('loan_payment_complete')
end

local function buyATM(source, payload, session)
    if not atmRequired(session) then return failure('card_required') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local existing = B.DB.single('SELECT owner_cid FROM codex_bank_atm_owners WHERE atm_id = ?', { session.atmId })
    if existing then return failure('atm_owned') end
    local card, cardError = checkCardSession(source, session, payload.accountId)
    if not card then return failure(cardError) end
    local account, err = accessToOwnChecking(source, payload.accountId)
    if not account then return failure(err) end
    local price = math.max(0, math.floor(tonumber(Config.ATMs.BasePrice) or 0))
    if account.balance < price then return failure('insufficient_funds') end
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { price, account.id, price }),
        queryObject('INSERT INTO codex_bank_atm_owners (atm_id, owner_cid, surcharge_percent, fee_balance) VALUES (?, ?, ?, 0)', { session.atmId, cid, Config.ATMs.DefaultSurchargePercent or 0 }),
        transactionLog(account.id, nil, cid, 'atm_purchase', price, 0, 'Player-owned ATM purchase')
    }
    if not B.DB.transaction(queries) then return failure('server_error') end
    B.SyncLegacy(cid)
    return success('atm_purchased')
end

local function setATMSurcharge(source, payload, session)
    if not atmRequired(session) then return failure('card_required') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local activeCard = B.DB.single('SELECT account_id FROM codex_bank_cards WHERE id = ? AND holder_cid = ?', { session.cardId, cid })
    if not activeCard then return failure('card_required') end
    local validCard, cardError = checkCardSession(source, session, activeCard.account_id)
    if not validCard then return failure(cardError) end
    local owner = B.DB.single('SELECT owner_cid FROM codex_bank_atm_owners WHERE atm_id = ?', { session.atmId })
    if not owner or owner.owner_cid ~= cid then return failure('no_permission') end
    local percent = tonumber(payload.percent)
    if not percent or percent < 0 or percent > Config.ATMs.OwnerSurchargeMaxPercent then return failure('invalid_amount') end
    B.DB.update('UPDATE codex_bank_atm_owners SET surcharge_percent = ? WHERE atm_id = ?', { percent, session.atmId })
    local saved = tonumber(B.DB.scalar('SELECT surcharge_percent FROM codex_bank_atm_owners WHERE atm_id = ?', { session.atmId }))
    if not saved or math.abs(saved - percent) > 0.01 then return failure('server_error') end
    return success('atm_surcharge_saved')
end

local function collectATM(source, payload, session)
    if not atmRequired(session) then return failure('card_required') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local card, cardError = checkCardSession(source, session, payload.accountId)
    if not card then return failure(cardError) end
    local owner = B.DB.single('SELECT owner_cid, fee_balance FROM codex_bank_atm_owners WHERE atm_id = ?', { session.atmId })
    if not owner or owner.owner_cid ~= cid then return failure('no_permission') end
    local amount = math.floor(tonumber(owner.fee_balance) or 0)
    if amount <= 0 then return failure('no_atm_earnings') end
    local account, err = accessToOwnChecking(source, payload.accountId)
    if not account then return failure(err) end
    if amount + account.balance > account.max_balance then return failure('destination_limit') end
    local queries = {
        queryObject('UPDATE codex_bank_atm_owners SET fee_balance = 0 WHERE atm_id = ? AND owner_cid = ? AND fee_balance >= ?', { session.atmId, cid, amount }),
        queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ? AND balance + ? <= max_balance', { amount, account.id, amount }),
        transactionLog(nil, account.id, cid, 'atm_collection', amount, 0, 'ATM service revenue')
    }
    if not B.DB.transaction(queries) then return failure('server_error') end
    B.SyncLegacy(cid)
    return success('atm_earnings_collected')
end

local function inventoryAvailable()
    return GetResourceState('ox_inventory') == 'started' or GetResourceState('qb-inventory') == 'started'
end

local function registerSafeBoxStash(box, citizenid)
    if not box or not box.stash_id or not inventoryAvailable() then return false end
    local ok, why = pcall(function()
        if GetResourceState('ox_inventory') == 'started' then
            exports.ox_inventory:RegisterStash(box.stash_id, 'CodeX Safe Box', tonumber(box.slots), tonumber(box.max_weight), citizenid)
        elseif GetResourceState('qb-inventory') == 'started' then
            exports['qb-inventory']:CreateInventory(box.stash_id, { label = 'CodeX Safe Box', slots = tonumber(box.slots), maxweight = tonumber(box.max_weight) })
        end
    end)
    if not ok and Config.Debug then
        print(('^3[%s] Could not register safe-box stash: %s^7'):format(GetCurrentResourceName(), tostring(why)))
    end
    return ok
end

local function rentSafeBox(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    if not Config.SafeBoxes.Enabled then return failure('feature_disabled') end
    if not inventoryAvailable() then return failure('inventory_unavailable') end

    local cid = B.GetCitizenId(B.GetPlayer(source))
    local tierSlots = B.Number(payload.slots, 1, 30)
    local tier = tierSlots and Config.SafeBoxes.Tiers[tierSlots]
    if not tier then return failure('invalid_tier') end
    local account, err = accessToOwnChecking(source, payload.accountId)
    if not account then return failure(err) end

    local existing = B.DB.single('SELECT * FROM codex_bank_safe_boxes WHERE owner_cid = ? ORDER BY id DESC LIMIT 1', { cid })
    local fee = math.max(0, math.floor(tonumber(tier.price) or 0))
    if account.balance < fee then return failure('insufficient_funds') end

    local stashId = existing and tostring(existing.stash_id) or nil
    if not existing then
        local digest = B.PinDigest(cid, 'safe-box', B.MakeReference('SAFE') .. ':' .. tostring(GetGameTimer() or 0))
        if type(digest) ~= 'string' or #digest ~= 64 then return failure('server_error') end
        -- Do not expose a predictable stash identifier to qb-inventory's stash event.
        stashId = 'codex_safe_' .. digest
    end

    local rentDays = math.max(1, math.floor(tonumber(Config.SafeBoxes.RentDays) or 7))
    local queries = {
        queryObject('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { fee, account.id, fee })
    }
    local feeVault = vaultQuery(account.bank_id, fee)
    if feeVault then queries[#queries + 1] = feeVault end
    queries[#queries + 1] = transactionLog(account.id, nil, cid, 'safe_box_rent', fee, 0, 'Safe deposit box rental')

    local boxId
    if existing then
        boxId = tonumber(existing.id)
        local updateBox = ([[
            UPDATE codex_bank_safe_boxes
            SET bank_id = ?, slots = ?, max_weight = ?,
                rent_expires_at = DATE_ADD(GREATEST(rent_expires_at, NOW()), INTERVAL %d DAY)
            WHERE id = ? AND owner_cid = ?
        ]]):format(rentDays)
        queries[#queries + 1] = queryObject(updateBox, { session.bankId, tier.slots, tier.maxWeight, boxId, cid })
    end

    if not B.DB.transaction(safeQueries(queries)) then return failure('server_error') end

    if not existing then
        local insertBox = ([[
            INSERT INTO codex_bank_safe_boxes (owner_cid, bank_id, stash_id, slots, max_weight, rent_expires_at)
            VALUES (?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL %d DAY))
        ]]):format(rentDays)
        boxId = B.DB.insert(insertBox, { cid, session.bankId, stashId, tier.slots, tier.maxWeight })
        if not boxId then
            B.DB.transaction({
                queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { fee, account.id }),
                queryObject('UPDATE codex_bank_vaults SET fee_balance = GREATEST(0, fee_balance - ?) WHERE bank_id = ?', { fee, account.bank_id }),
                transactionLog(nil, account.id, cid, 'safe_box_refund', fee, 0, 'Safe box rental reversal')
            })
            return failure('server_error')
        end
    end

    local box = B.DB.single('SELECT * FROM codex_bank_safe_boxes WHERE id = ? AND owner_cid = ?', { boxId, cid })
    if not box then
        B.DB.transaction({
            queryObject('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { fee, account.id }),
            queryObject('UPDATE codex_bank_vaults SET fee_balance = GREATEST(0, fee_balance - ?) WHERE bank_id = ?', { fee, account.bank_id }),
            transactionLog(nil, account.id, cid, 'safe_box_refund', fee, 0, 'Safe box rental reversal')
        })
        return failure('server_error')
    end
    registerSafeBoxStash(box, cid)
    B.SyncLegacy(cid)
    return success('safe_box_rented')
end

local function openSafeBox(source, payload, session)
    if not branchRequired(session) then return failure('branch_only') end
    local cid = B.GetCitizenId(B.GetPlayer(source))
    local boxId = B.Number(payload.boxId, 1, 2147483647)
    if not boxId then return failure('safe_box_not_found') end
    local box = B.DB.single('SELECT * FROM codex_bank_safe_boxes WHERE id = ? AND owner_cid = ? LIMIT 1', { boxId, cid })
    if not box then return failure('safe_box_not_found') end
    if tostring(box.bank_id) ~= tostring(session.bankId) then return failure('branch_only') end
    if tostring(box.rent_expires_at) < os.date('%Y-%m-%d %H:%M:%S') then return failure('safe_box_expired') end
    if not inventoryAvailable() then return failure('inventory_unavailable') end
    if not registerSafeBoxStash(box, cid) then return failure('server_error') end
    TriggerClientEvent('codex_banking:client:openSafeBox', source, {
        id = tonumber(box.id), stashId = box.stash_id, slots = tonumber(box.slots), maxWeight = tonumber(box.max_weight), owner = cid
    })
    return success('safe_box_opened', { refresh = false })
end

local function actionHandler(source, action, payload, session)
    local dispatch = {
        unlockCard = function() return unlockCard(source, payload, session) end,
        openChecking = function() return openNewChecking(source, payload, session) end,
        openSavings = function() return openSavings(source, payload, session) end,
        createSharedAccount = function() return createSharedAccount(source, payload, session) end,
        addMember = function() return addSharedMember(source, payload, session) end,
        removeMember = function() return removeSharedMember(source, payload, session) end,
        upgradeAccount = function() return upgradeAccount(source, payload, session) end,
        setSavingsGoal = function() return setSavingsGoal(source, payload, session) end,
        createCard = function() return createCard(source, payload, session) end,
        freezeCard = function() return setCardFreeze(source, payload, session) end,
        deposit = function() return deposit(source, payload, session) end,
        withdraw = function() return withdraw(source, payload, session) end,
        transfer = function() return sendTransfer(source, payload, session) end,
        createInvoice = function() return newInvoice(source, payload, session) end,
        payInvoice = function() return payInvoice(source, payload, session) end,
        issueCheque = function() return issueCheque(source, payload, session) end,
        cashCheque = function() return cashCheque(source, payload, session) end,
        cancelCheque = function() return cancelCheque(source, payload, session) end,
        applyLoan = function() return applyLoan(source, payload, session) end,
        payLoan = function() return payLoan(source, payload, session) end,
        buyATM = function() return buyATM(source, payload, session) end,
        setATMSurcharge = function() return setATMSurcharge(source, payload, session) end,
        collectATM = function() return collectATM(source, payload, session) end,
        rentSafeBox = function() return rentSafeBox(source, payload, session) end,
        openSafeBox = function() return openSafeBox(source, payload, session) end
    }
    local handler = dispatch[action]
    if not handler then return failure('unknown_action') end
    return handler()
end

QBCore.Functions.CreateCallback('codex_banking:server:action', function(source, cb, action, payload, token)
    if not B.Ready then cb(failure('not_ready')) return end
    if type(action) ~= 'string' or #action > 40 then cb(failure('unknown_action')) return end
    if type(payload) ~= 'table' then payload = {} end

    local session = B.SessionFor(source, token)
    if not session then cb(failure('session_expired')) return end
    if session.mode == 'admin' then
        cb(failure('admin_action_required'))
        return
    end

    local now = GetGameTimer() or 0
    local last = B.LastActionAt[source] or 0
    if now - last < (tonumber(Config.Security.ActionCooldownMs) or 350) then
        cb(failure('slow_down'))
        return
    end
    B.LastActionAt[source] = now

    local response = B.WithLock(function()
        local liveSession = B.SessionFor(source, token)
        if not liveSession then return failure('session_expired') end
        if action ~= 'unlockCard' and liveSession.mode == 'atm_pending' then return failure('card_required') end
        if not B.ReconcileLegacy(source) then return failure('server_error') end
        local result = actionHandler(source, action, payload, liveSession)
        return refreshResult(source, liveSession, result)
    end)
    cb(response)
end)

RegisterNetEvent('codex_banking:server:closeSession', function(token)
    local src = source
    local session = B.Sessions[src]
    if session and (not token or session.token == token) then
        B.Sessions[src] = nil
    end
end)
