local RESOURCE = GetCurrentResourceName()
local QBCore = exports['qb-core']:GetCoreObject()

CodexBanking = CodexBanking or {}
local B = CodexBanking

B.QBCore = QBCore
B.Ready = false
B.Busy = false
B.Sessions = {}
B.Settings = {}
B.LastActionAt = {}
B.DB = {}

local function debugPrint(...)
    if Config.Debug then
        print(('^3[%s]^7'):format(RESOURCE), ...)
    end
end

local function dbCall(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        print(('^1[%s] database error in %s: %s^7'):format(RESOURCE, label, tostring(result)))
        return nil, false
    end
    return result, true
end

function B.DB.query(query, values)
    local result, ok = dbCall('query', MySQL.query.await, query, values or {})
    return ok and result or {}
end

function B.DB.single(query, values)
    local result, ok = dbCall('single', MySQL.single.await, query, values or {})
    return ok and result or nil
end

function B.DB.scalar(query, values)
    local result, ok = dbCall('scalar', MySQL.scalar.await, query, values or {})
    return ok and result or nil
end

function B.DB.update(query, values)
    local result, ok = dbCall('update', MySQL.update.await, query, values or {})
    return ok and tonumber(result) or 0
end

function B.DB.insert(query, values)
    local result, ok = dbCall('insert', MySQL.insert.await, query, values or {})
    return ok and tonumber(result) or nil
end

function B.DB.transaction(queries)
    local result, ok = dbCall('transaction', MySQL.transaction.await, queries)
    return ok and result == true
end

function B.WithLock(callback)
    if B.Busy then
        return { ok = false, message = 'busy' }
    end

    B.Busy = true
    local ok, result = xpcall(callback, debug.traceback)
    B.Busy = false

    if not ok then
        print(('^1[%s] operation failed: %s^7'):format(RESOURCE, tostring(result)))
        return { ok = false, message = 'server_error' }
    end

    return result or { ok = false, message = 'server_error' }
end

function B.Number(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    if number % 1 ~= 0 then
        return nil
    end
    if minimum and number < minimum then
        return nil
    end
    if maximum and number > maximum then
        return nil
    end
    return number
end

function B.Trim(value, maxLength)
    if type(value) ~= 'string' then
        return ''
    end
    local clean = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLength and #clean > maxLength then
        clean = clean:sub(1, maxLength)
    end
    return clean
end

function B.MakeReference(prefix)
    local safePrefix = tostring(prefix or 'TX'):upper():gsub('[^A-Z0-9]', ''):sub(1, 8)
    if safePrefix == '' then safePrefix = 'TX' end
    return ('%s-%x-%x-%04x'):format(safePrefix, os.time(), GetGameTimer() or 0, math.random(0, 65535))
end

function B.GetPlayer(source)
    return QBCore.Functions.GetPlayer(tonumber(source))
end

function B.GetPlayerByCitizenId(citizenid)
    return QBCore.Functions.GetPlayerByCitizenId(citizenid)
end

function B.GetCitizenId(player)
    if not player or not player.PlayerData then
        return nil
    end
    return player.PlayerData.citizenid
end

function B.GetName(player)
    local info = player and player.PlayerData and player.PlayerData.charinfo or {}
    local name = (tostring(info.firstname or '') .. ' ' .. tostring(info.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or 'Resident'
end

function B.GetMoney(player, moneyType)
    if not player or not player.PlayerData or type(player.PlayerData.money) ~= 'table' then
        return 0
    end
    return math.max(0, math.floor(tonumber(player.PlayerData.money[moneyType]) or 0))
end

function B.SetLegacyBank(player, amount, reason)
    if not Config.LegacySync or Config.LegacySync.Enabled == false or not player then
        return false
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local ok = pcall(function()
        player.Functions.SetMoney('bank', amount, reason or 'codex-banking-sync')
    end)
    return ok
end

function B.IsAdmin(source)
    source = tonumber(source)
    if not source then
        return false
    end
    if Config.Security.AdminAce and IsPlayerAceAllowed(source, Config.Security.AdminAce) then
        return true
    end
    local player = B.GetPlayer(source)
    if not player then
        return false
    end
    local group = player.PlayerData and player.PlayerData.group
    if group and Config.Admin and Config.Admin.QBCorePermissions then
        for _, allowed in ipairs(Config.Admin.QBCorePermissions) do
            if group == allowed then
                return true
            end
        end
    end
    for _, permission in ipairs((Config.Admin and Config.Admin.QBCorePermissions) or {}) do
        local ok, allowed = pcall(QBCore.Functions.HasPermission, source, permission)
        if ok and allowed then
            return true
        end
    end
    return false
end

local function distance(first, second)
    if not first or not second then
        return math.huge
    end
    local dx = (first.x or first[1] or 0.0) - (second.x or second[1] or 0.0)
    local dy = (first.y or first[2] or 0.0) - (second.y or second[2] or 0.0)
    local dz = (first.z or first[3] or 0.0) - (second.z or second[3] or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function B.PlayerCoords(source)
    local ped = GetPlayerPed(tonumber(source))
    if not ped or ped == 0 then
        return nil
    end
    local coords = GetEntityCoords(ped)
    return coords
end

function B.NearestBranch(source, bankId)
    local coords = B.PlayerCoords(source)
    if not coords then
        return nil
    end

    local best, bestDistance
    for _, branch in ipairs(Config.Branches or {}) do
        if not bankId or branch.bank == bankId then
            local current = distance(coords, branch.coords)
            local limit = tonumber(branch.radius) or 4.0
            if current <= limit and (not bestDistance or current < bestDistance) then
                best, bestDistance = branch, current
            end
        end
    end
    return best, bestDistance
end

function B.NearestATM(source, maxDistance)
    if not Config.ATMs or Config.ATMs.Enabled == false then
        return nil
    end
    local coords = B.PlayerCoords(source)
    if not coords then
        return nil
    end

    local bestId, bestDistance
    for index, atmCoords in ipairs(Config.ATMs.AccessPoints or {}) do
        local current = distance(coords, atmCoords)
        if current <= (tonumber(maxDistance) or tonumber(Config.ATMs.InteractionRadius) or 2.5) and (not bestDistance or current < bestDistance) then
            bestId, bestDistance = index, current
        end
    end
    return bestId, bestDistance
end

function B.SessionFor(source, token)
    local session = B.Sessions[tonumber(source)]
    if not session or type(token) ~= 'string' or session.token ~= token then
        return nil
    end
    if session.expiresAt < os.time() then
        B.Sessions[tonumber(source)] = nil
        return nil
    end
    if session.mode == 'admin' then
        if not B.IsAdmin(source) then
            B.Sessions[tonumber(source)] = nil
            return nil
        end
    elseif session.mode == 'branch' then
        local coords = B.PlayerCoords(source)
        local branch
        for _, item in ipairs(Config.Branches or {}) do
            if item.id == session.branchId and item.bank == session.bankId then branch = item break end
        end
        local allowedDistance = branch and (tonumber(branch.radius) or 4.0) or 0
        if not branch or distance(coords, branch.coords) > allowedDistance then
            return nil
        end
    elseif session.mode == 'atm' or session.mode == 'atm_pending' then
        local atmId = B.NearestATM(source, Config.ATMs.SessionRadius)
        if not atmId or atmId ~= session.atmId then
            return nil
        end
    else
        return nil
    end
    return session
end

function B.NewSession(source, mode, metadata)
    local token = ('%x-%x-%04x'):format(os.time(), GetGameTimer() or 0, math.random(0, 65535))
    local session = metadata or {}
    session.token = token
    session.mode = mode
    session.expiresAt = os.time() + (tonumber(Config.Security.SessionSeconds) or 300)
    B.Sessions[tonumber(source)] = session
    return session
end

function B.AccountNumber(bankId)
    local bank = Config.Banks[bankId]
    if not bank then
        return nil
    end
    for _ = 1, 20 do
        local value = ('%s%010d'):format(bank.prefix or 'CX', math.random(0, 9999999999))
        if not B.DB.single('SELECT id FROM codex_bank_accounts WHERE account_no = ? LIMIT 1', { value }) then
            return value
        end
    end
    return nil
end

local pinWarningShown = false
function B.PinDigest(citizenid, cardId, pin)
    local secret = GetConvar((Config.Security and Config.Security.PinSecretConvar) or 'codex_banking:pinSecret', '')
    if secret == '' then
        secret = RESOURCE .. ':change-this-server-convar'
        if not pinWarningShown then
            pinWarningShown = true
            print(('^3[%s] WARNING: Set the %s server convar to a long random secret to protect card PIN verifiers.^7'):format(RESOURCE, Config.Security.PinSecretConvar))
        end
    end
    return B.DB.scalar("SELECT SHA2(CONCAT(?, '|', ?, '|', ?, '|', ?), 256)", {
        secret, tostring(citizenid), tostring(cardId), tostring(pin)
    })
end

function B.CreditScore(citizenid)
    local score = tonumber(B.DB.scalar('SELECT score FROM codex_bank_credit_scores WHERE citizenid = ?', { citizenid }))
    if not score then
        B.DB.query('INSERT IGNORE INTO codex_bank_credit_scores (citizenid, score) VALUES (?, 650)', { citizenid })
        return 650
    end
    return math.min(850, math.max(300, math.floor(score)))
end

function B.AdjustCredit(citizenid, delta)
    B.DB.query([[
        INSERT INTO codex_bank_credit_scores (citizenid, score)
        VALUES (?, LEAST(850, GREATEST(300, 650 + ?)))
        ON DUPLICATE KEY UPDATE score = LEAST(850, GREATEST(300, score + VALUES(score) - 650))
    ]], { citizenid, math.floor(tonumber(delta) or 0) })
end

function B.PersonalTotal(citizenid)
    return math.max(0, math.floor(tonumber(B.DB.scalar([[
        SELECT COALESCE(SUM(balance), 0) FROM codex_bank_accounts
        WHERE owner_cid = ? AND account_type IN ('checking', 'savings')
    ]], { citizenid })) or 0))
end

function B.UpdateOfflineBank(citizenid, amount)
    if not Config.LegacySync or Config.LegacySync.Enabled == false then
        return
    end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local online = B.GetPlayerByCitizenId(citizenid)
    local mirrored = false
    if online then
        B.SetLegacyBank(online, amount, 'codex-banking-ledger')
        mirrored = B.GetMoney(online, 'bank') == amount
    else
        -- QBCore stores money as JSON in players.money. The DB call is only a
        -- compatibility mirror; the CodeX ledger remains the source of truth.
        local changed = B.DB.update("UPDATE players SET money = JSON_SET(money, '$.bank', ?) WHERE citizenid = ?", { amount, citizenid })
        mirrored = changed > 0
        if not mirrored then
            local persisted = B.DB.scalar("SELECT CAST(JSON_UNQUOTE(JSON_EXTRACT(money, '$.bank')) AS SIGNED) FROM players WHERE citizenid = ?", { citizenid })
            mirrored = tonumber(persisted) == amount
        end
    end
    if not mirrored then return end
    B.DB.query([[
        INSERT INTO codex_bank_legacy_sync (citizenid, last_bank_balance)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE last_bank_balance = VALUES(last_bank_balance)
    ]], { citizenid, amount })
end

function B.ReconcileLegacy(source)
    if not Config.LegacySync or Config.LegacySync.Enabled == false then
        return true
    end
    local player = B.GetPlayer(source)
    local citizenid = B.GetCitizenId(player)
    if not citizenid then
        return false
    end
    local sync = B.DB.single('SELECT last_bank_balance FROM codex_bank_legacy_sync WHERE citizenid = ?', { citizenid })
    if not sync then
        local existingAccount = B.DB.single([[
            SELECT id FROM codex_bank_accounts
            WHERE owner_cid = ? AND account_type IN ('checking', 'savings')
            LIMIT 1
        ]], { citizenid })
        if not existingAccount then
            return true -- First account open imports the player's existing QBCore bank balance.
        end

        -- If a sync row was removed during an upgrade or manual cleanup, never
        -- import the legacy balance into another account and duplicate funds.
        local total = B.PersonalTotal(citizenid)
        local actual = B.GetMoney(player, 'bank')
        if actual ~= total then B.SetLegacyBank(player, total, 'codex-banking-reconcile') end
        local baseline = B.GetMoney(player, 'bank') == total and total or actual
        B.DB.query([[
            INSERT INTO codex_bank_legacy_sync (citizenid, last_bank_balance)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE last_bank_balance = VALUES(last_bank_balance)
        ]], { citizenid, baseline })
        return true
    end

    local actual = B.GetMoney(player, 'bank')
    local previous = math.max(0, math.floor(tonumber(sync.last_bank_balance) or 0))
    local delta = actual - previous
    if delta ~= 0 then
        local accounts = B.DB.query([[
            SELECT id, balance, account_type FROM codex_bank_accounts
            WHERE owner_cid = ? AND account_type IN ('checking', 'savings')
            ORDER BY CASE WHEN account_type = 'checking' THEN 0 ELSE 1 END, id ASC
        ]], { citizenid })

        if delta > 0 and accounts[1] then
            B.DB.update('UPDATE codex_bank_accounts SET balance = balance + ? WHERE id = ?', { delta, accounts[1].id })
        elseif delta < 0 then
            local remaining = -delta
            for _, account in ipairs(accounts) do
                if remaining <= 0 then break end
                local available = math.max(0, math.floor(tonumber(account.balance) or 0))
                local take = math.min(available, remaining)
                if take > 0 then
                    B.DB.update('UPDATE codex_bank_accounts SET balance = balance - ? WHERE id = ? AND balance >= ?', { take, account.id, take })
                    remaining = remaining - take
                end
            end
        end
    end

    local total = B.PersonalTotal(citizenid)
    if actual ~= total then
        B.SetLegacyBank(player, total, 'codex-banking-reconcile')
    end
    local baseline = B.GetMoney(player, 'bank') == total and total or actual
    B.DB.query([[
        INSERT INTO codex_bank_legacy_sync (citizenid, last_bank_balance)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE last_bank_balance = VALUES(last_bank_balance)
    ]], { citizenid, baseline })
    return true
end

function B.SyncLegacy(citizenid)
    if not Config.LegacySync or Config.LegacySync.Enabled == false then
        return
    end
    B.UpdateOfflineBank(citizenid, B.PersonalTotal(citizenid))
end

function B.AccountAccess(source, accountId)
    local player = B.GetPlayer(source)
    local citizenid = B.GetCitizenId(player)
    if not player or not citizenid then
        return nil, 'not_authenticated'
    end
    accountId = tonumber(accountId)
    if not accountId or accountId < 1 then
        return nil, 'account_not_found'
    end

    local account = B.DB.single('SELECT * FROM codex_bank_accounts WHERE id = ? LIMIT 1', { accountId })
    if not account then
        return nil, 'account_not_found'
    end
    account.id = tonumber(account.id)
    account.balance = math.floor(tonumber(account.balance) or 0)
    account.daily_limit = math.floor(tonumber(account.daily_limit) or 0)
    account.max_balance = math.floor(tonumber(account.max_balance) or 0)

    local member = B.DB.single('SELECT role, daily_limit, daily_spent, daily_spent_date FROM codex_bank_account_members WHERE account_id = ? AND citizenid = ?', { account.id, citizenid })
    if member then
        local role = tostring(member.role or 'member')
        local definition = Config.Accounts.Roles[role] or Config.Accounts.Roles.member
        account.member_role = role
        account.canWithdraw = definition.canWithdraw == true
        account.canTransfer = definition.canTransfer == true
        account.canManage = definition.canManage == true
        account.member_daily_limit = math.floor(tonumber(member.daily_limit) or definition.dailyLimit or 0)
        account.member_daily_spent = math.floor(tonumber(member.daily_spent) or 0)
        account.member_daily_date = member.daily_spent_date
        account.access = true
        return account, nil, player, citizenid
    end

    if account.owner_cid and account.owner_cid == citizenid then
        account.member_role = 'owner'
        account.canWithdraw, account.canTransfer, account.canManage, account.access = true, true, true, true
        account.member_daily_limit = (Config.Accounts.Roles.owner and Config.Accounts.Roles.owner.dailyLimit) or 10000000
        account.member_daily_spent = 0
        return account, nil, player, citizenid
    end

    if account.account_type == 'company' and account.job_name then
        local jobConfig = Config.JobAccounts[account.job_name]
        local job = player.PlayerData and player.PlayerData.job or {}
        local grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade)
        grade = grade or 0
        if jobConfig and job.name == account.job_name and grade >= (tonumber(jobConfig.accessGrade) or 0) then
            account.member_role = grade >= (tonumber(jobConfig.manageGrade) or 99) and 'owner' or (grade >= (tonumber(jobConfig.withdrawGrade) or 99) and 'admin' or 'viewer')
            account.canWithdraw = grade >= (tonumber(jobConfig.withdrawGrade) or 99)
            account.canTransfer = account.canWithdraw
            account.canManage = grade >= (tonumber(jobConfig.manageGrade) or 99)
            account.member_daily_limit = math.floor(tonumber(jobConfig.dailyLimit) or 100000)
            account.member_daily_spent = 0
            account.access = true
            return account, nil, player, citizenid
        end
    end

    return nil, 'account_not_found'
end

function B.GetAccessForCitizen(citizenid, accountId)
    local account = B.DB.single('SELECT * FROM codex_bank_accounts WHERE id = ? LIMIT 1', { accountId })
    if not account then return nil end
    if account.owner_cid == citizenid then
        account.member_role = 'owner'
        account.canManage, account.canWithdraw, account.canTransfer = true, true, true
        return account
    end
    local member = B.DB.single('SELECT role FROM codex_bank_account_members WHERE account_id = ? AND citizenid = ?', { accountId, citizenid })
    if member then
        local role = Config.Accounts.Roles[member.role] or Config.Accounts.Roles.member
        account.member_role = member.role
        account.canManage, account.canWithdraw, account.canTransfer = role.canManage, role.canWithdraw, role.canTransfer
        return account
    end
    return nil
end

local function accountForUi(account, citizenid)
    local bank = Config.Banks[account.bank_id] or {}
    return {
        id = tonumber(account.id),
        accountNo = tostring(account.account_no or ''),
        bankId = tostring(account.bank_id or ''),
        bankLabel = bank.label or tostring(account.bank_id or ''),
        bankColor = bank.color or '#49c5b6',
        type = tostring(account.account_type or 'checking'),
        label = tostring(account.label or ''),
        isPersonal = account.owner_cid ~= nil and account.owner_cid == citizenid,
        balance = math.floor(tonumber(account.balance) or 0),
        dailyLimit = math.floor(tonumber(account.daily_limit) or 0),
        maxBalance = math.floor(tonumber(account.max_balance) or 0),
        level = math.floor(tonumber(account.account_level) or 1),
        savingsTier = math.floor(tonumber(account.savings_tier) or 0),
        savingsGoal = math.floor(tonumber(account.savings_goal) or 0),
        savingsGoalLabel = tostring(account.savings_goal_label or ''),
        role = tostring(account.member_role or 'member'),
        canWithdraw = account.canWithdraw == true,
        canTransfer = account.canTransfer == true,
        canManage = account.canManage == true,
        memberDailyLimit = math.floor(tonumber(account.member_daily_limit) or 0),
        memberDailySpent = math.floor(tonumber(account.member_daily_spent) or 0),
        members = account.canManage and (account.members or {}) or nil
    }
end

function B.GetCards(citizenid)
    local cards = B.DB.query([[
        SELECT c.id, c.account_id, c.tier, c.last4, c.is_frozen, c.locked_until,
               c.daily_limit, c.daily_spent, c.daily_spent_date,
               a.account_no, a.bank_id, a.label AS account_label
        FROM codex_bank_cards c
        JOIN codex_bank_accounts a ON a.id = c.account_id
        WHERE c.holder_cid = ?
        ORDER BY c.id DESC
    ]], { citizenid })
    for _, card in ipairs(cards) do
        local tier = Config.Cards.Tiers[card.tier] or Config.Cards.Tiers.standard
        card.id = tonumber(card.id)
        card.account_id = tonumber(card.account_id)
        card.daily_limit = tonumber(card.daily_limit) or 0
        card.daily_spent = tonumber(card.daily_spent) or 0
        card.daily_remaining = tostring(card.daily_spent_date or '') == os.date('%Y-%m-%d') and math.max(0, card.daily_limit - card.daily_spent) or card.daily_limit
        card.frozen = tonumber(card.is_frozen) == 1
        card.tier_label = tier.label
        card.color = tier.color
        card.is_frozen = nil
    end
    return cards
end

function B.GetDashboard(source, session)
    local player = B.GetPlayer(source)
    local citizenid = B.GetCitizenId(player)
    if not player or not citizenid then
        return nil
    end

    local rows = B.DB.query([[
        SELECT a.*, m.role AS member_role, m.daily_limit AS member_daily_limit,
               m.daily_spent AS member_daily_spent, m.daily_spent_date AS member_daily_date
        FROM codex_bank_accounts a
        LEFT JOIN codex_bank_account_members m ON m.account_id = a.id AND m.citizenid = ?
        WHERE a.owner_cid = ? OR m.citizenid = ?
        ORDER BY CASE a.account_type WHEN 'checking' THEN 0 WHEN 'savings' THEN 1 WHEN 'shared' THEN 2 ELSE 3 END, a.id ASC
    ]], { citizenid, citizenid, citizenid })

    for _, row in ipairs(rows) do
        row.id = tonumber(row.id)
        if row.account_type == 'shared' then
            row.members = B.DB.query('SELECT citizenid, role FROM codex_bank_account_members WHERE account_id = ? ORDER BY role, citizenid', { row.id })
        end
        row.balance = math.floor(tonumber(row.balance) or 0)
        row.daily_limit = math.floor(tonumber(row.daily_limit) or 0)
        row.max_balance = math.floor(tonumber(row.max_balance) or 0)
        local roleName = row.member_role or (row.owner_cid == citizenid and 'owner' or 'viewer')
        local role = Config.Accounts.Roles[roleName] or Config.Accounts.Roles.member
        row.member_role = roleName
        row.canWithdraw = role.canWithdraw == true
        row.canTransfer = role.canTransfer == true
        row.canManage = role.canManage == true
        row.member_daily_limit = tonumber(row.member_daily_limit) or role.dailyLimit or 0
        row.member_daily_spent = tonumber(row.member_daily_spent) or 0
    end

    local job = player.PlayerData and player.PlayerData.job or {}
    local jobConfig = job.name and Config.JobAccounts[job.name]
    if jobConfig then
        local grade = type(job.grade) == 'table' and tonumber(job.grade.level) or tonumber(job.grade)
        grade = grade or 0
        if grade >= (tonumber(jobConfig.accessGrade) or 0) then
            local company = B.DB.single('SELECT * FROM codex_bank_accounts WHERE account_type = \'company\' AND job_name = ? LIMIT 1', { job.name })
            if company then
                company.id = tonumber(company.id)
                company.balance = math.floor(tonumber(company.balance) or 0)
                company.daily_limit = math.floor(tonumber(company.daily_limit) or 0)
                company.max_balance = math.floor(tonumber(company.max_balance) or 0)
                company.member_role = grade >= (tonumber(jobConfig.manageGrade) or 99) and 'owner' or (grade >= (tonumber(jobConfig.withdrawGrade) or 99) and 'admin' or 'viewer')
                company.canWithdraw = grade >= (tonumber(jobConfig.withdrawGrade) or 99)
                company.canTransfer = company.canWithdraw
                company.canManage = grade >= (tonumber(jobConfig.manageGrade) or 99)
                company.member_daily_limit = tonumber(jobConfig.dailyLimit) or 0
                company.member_daily_spent = 0
                rows[#rows + 1] = company
            end
        end
    end

    if session and session.mode == 'atm' and session.cardId then
        local card = B.DB.single('SELECT account_id FROM codex_bank_cards WHERE id = ? AND holder_cid = ?', { session.cardId, citizenid })
        local cardAccount = card and tonumber(card.account_id)
        local filtered = {}
        for _, account in ipairs(rows) do
            if account.id == cardAccount then
                filtered[#filtered + 1] = account
            end
        end
        rows = filtered
    end

    local accounts = {}
    local accountIds = {}
    for _, account in ipairs(rows) do
        accounts[#accounts + 1] = accountForUi(account, citizenid)
        accountIds[#accountIds + 1] = tonumber(account.id)
    end

    local transactions = {}
    if #accountIds > 0 then
        local placeholders = {}
        local values = {}
        for _, id in ipairs(accountIds) do
            placeholders[#placeholders + 1] = '?'
            values[#values + 1] = id
        end
        local list = table.concat(placeholders, ',')
        transactions = B.DB.query(([[
            SELECT t.id, t.reference, t.from_account_id, t.to_account_id, t.actor_cid,
                   t.type, t.amount, t.fee, t.description, t.created_at,
                   fa.account_no AS from_account_no, ta.account_no AS to_account_no
            FROM codex_bank_transactions t
            LEFT JOIN codex_bank_accounts fa ON fa.id = t.from_account_id
            LEFT JOIN codex_bank_accounts ta ON ta.id = t.to_account_id
            WHERE t.from_account_id IN (%s) OR t.to_account_id IN (%s)
            ORDER BY t.id DESC LIMIT 30
        ]]):format(list, list), (function()
            local both = {}
            for _, value in ipairs(values) do both[#both + 1] = value end
            for _, value in ipairs(values) do both[#both + 1] = value end
            return both
        end)())
    end

    local cards = B.GetCards(citizenid)
    if session and session.mode == 'atm' and session.cardId then
        local activeCards = {}
        for _, card in ipairs(cards) do
            if tonumber(card.id) == tonumber(session.cardId) then activeCards[#activeCards + 1] = card end
        end
        cards = activeCards
    end
    local loans = B.DB.query('SELECT id, reference, plan_id, principal, balance, interest_rate, due_at, status, collateral_plate FROM codex_bank_loans WHERE borrower_cid = ? ORDER BY id DESC LIMIT 20', { citizenid })
    for _, loan in ipairs(loans) do
        loan.id = tonumber(loan.id)
        loan.principal = tonumber(loan.principal) or 0
        loan.balance = tonumber(loan.balance) or 0
        loan.interest_rate = tonumber(loan.interest_rate) or 0
    end

    local invoices = B.DB.query([[
        SELECT id, reference, issuer_cid, recipient_cid, issuer_account_id, amount, reason, status, due_at, created_at
        FROM codex_bank_invoices
        WHERE (recipient_cid = ? AND status = 'pending') OR issuer_cid = ?
        ORDER BY id DESC LIMIT 30
    ]], { citizenid, citizenid })
    for _, invoice in ipairs(invoices) do
        invoice.id = tonumber(invoice.id)
        invoice.issuer_account_id = tonumber(invoice.issuer_account_id)
        invoice.amount = tonumber(invoice.amount) or 0
        invoice.is_recipient = invoice.recipient_cid == citizenid
    end

    local cheques = B.DB.query([[
        SELECT id, cheque_no, issuer_cid, beneficiary_cid, account_id, amount, reason, status, expires_at, created_at
        FROM codex_bank_cheques
        WHERE issuer_cid = ? OR beneficiary_cid = ?
        ORDER BY id DESC LIMIT 30
    ]], { citizenid, citizenid })
    for _, cheque in ipairs(cheques) do
        cheque.id = tonumber(cheque.id)
        cheque.account_id = tonumber(cheque.account_id)
        cheque.amount = tonumber(cheque.amount) or 0
        cheque.is_beneficiary = cheque.beneficiary_cid == citizenid
    end

    local safeBoxes = B.DB.query([[
        SELECT id, bank_id, slots, max_weight, rent_expires_at, stash_id
        FROM codex_bank_safe_boxes WHERE owner_cid = ? ORDER BY id DESC
    ]], { citizenid })
    for _, box in ipairs(safeBoxes) do
        box.id = tonumber(box.id)
        box.slots = tonumber(box.slots)
        box.max_weight = tonumber(box.max_weight)
        -- NUI does not need the raw stash name; the server sends it only to the client on open.
        box.stash_id = nil
    end

    local score = B.CreditScore(citizenid)
    local banks = {}
    for id, bank in pairs(Config.Banks) do
        banks[#banks + 1] = { id = id, label = bank.label, color = bank.color }
    end
    table.sort(banks, function(left, right) return left.label < right.label end)

    return {
        user = { citizenid = citizenid, name = B.GetName(player), job = job.label or job.name or '' },
        cash = B.GetMoney(player, 'cash'),
        legacyBank = B.GetMoney(player, 'bank'),
        creditScore = score,
        accounts = accounts,
        cards = cards,
        transactions = transactions,
        loans = loans,
        invoices = invoices,
        cheques = cheques,
        safeBoxes = safeBoxes,
        banks = banks,
        session = session and { mode = session.mode, bankId = session.bankId, branchId = session.branchId, atmId = session.atmId, cardId = session.cardId } or {},
        plans = Config.Loans.Plans,
        cardTiers = Config.Cards.Tiers,
        savingsTiers = Config.Savings.Tiers,
        safeBoxTiers = Config.SafeBoxes.Tiers,
        limits = {
            maxAmount = Config.Security.MaxAmount,
            invoiceMaxAmount = Config.Invoices.MaxAmount,
            chequeMaxAmount = Config.Cheques.MaxAmount,
            interBankFeePercent = B.Settings.interBankFeePercent
        },
        chequeEnabled = Config.Cheques.Enabled == true,
        safeBoxesEnabled = Config.SafeBoxes.Enabled == true
    }
end

function B.AccountForUiById(source, accountId)
    local account, _, _, citizenid = B.AccountAccess(source, accountId)
    return account and accountForUi(account, citizenid) or nil
end

function B.Notify(source, message, kind)
    TriggerClientEvent('codex_banking:client:notify', tonumber(source), message, kind or 'primary')
end

local function executeSchema()
    if Config.Database and Config.Database.AutoCreate == false then
        return true
    end
    local schema = LoadResourceFile(RESOURCE, 'sql/codex_banking.sql')
    if not schema then
        print(('^1[%s] sql/codex_banking.sql could not be loaded.^7'):format(RESOURCE))
        return false
    end
    local statements = 0
    for statement in schema:gmatch('([^;]+);') do
        local sql = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if sql ~= '' then
            local _, ok = dbCall('schema', MySQL.query.await, sql, {})
            if not ok then return false end
            statements = statements + 1
        end
    end
    debugPrint(('Created/checked %d schema tables.'):format(statements))
    return true
end

local function seedDefaults()
    for bankId in pairs(Config.Banks) do
        B.DB.query('INSERT IGNORE INTO codex_bank_vaults (bank_id, fee_balance) VALUES (?, 0)', { bankId })
    end

    for jobName, jobConfig in pairs(Config.JobAccounts or {}) do
        local exists = B.DB.single("SELECT id FROM codex_bank_accounts WHERE account_type = 'company' AND job_name = ? LIMIT 1", { jobName })
        if not exists then
            local bankId = Config.Banks[jobConfig.bank] and jobConfig.bank or next(Config.Banks)
            local accountNo = ('JOB-%s'):format(jobName:upper():gsub('[^A-Z0-9]', ''):sub(1, 12))
            B.DB.insert([[
                INSERT IGNORE INTO codex_bank_accounts
                    (account_no, bank_id, account_type, label, owner_cid, job_name, balance, daily_limit, max_balance, account_level)
                VALUES (?, ?, 'company', ?, NULL, ?, 0, ?, ?, 1)
            ]], { accountNo, bankId, jobConfig.label or jobName, jobName, tonumber(jobConfig.dailyLimit) or 100000, Config.Accounts.DefaultMaxBalance })
        end
    end

    local fee = tonumber(B.DB.scalar("SELECT setting_value FROM codex_bank_settings WHERE setting_key = 'inter_bank_fee_percent'", {}))
    local maxFee = math.max(0, tonumber(Config.Admin.MaxRuntimeTransferFeePercent) or 5.0) / 100
    local configuredFee = fee or tonumber(Config.Transfer.InterBankFeePercent) or 0.005
    B.Settings.interBankFeePercent = math.max(0, math.min(maxFee, configuredFee))
end

CreateThread(function()
    math.randomseed(os.time() + (GetGameTimer() or 0))
    Wait(500)
    if not executeSchema() then
        print(('^1[%s] Banking is disabled until the SQL schema is available.^7'):format(RESOURCE))
        return
    end
    seedDefaults()
    B.Ready = true
    print(('^2[%s] QBCore banking is ready. %d bank networks, %d branches.^7'):format(RESOURCE, (function() local n=0 for _ in pairs(Config.Banks) do n=n+1 end return n end)(), #Config.Branches))
end)

RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(playerSource)
    local sourceId = tonumber(playerSource) or source
    B.Sessions[sourceId] = nil
end)

AddEventHandler('playerDropped', function()
    B.Sessions[source] = nil
    B.LastActionAt[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then
        B.Sessions = {}
    end
end)

exports('GetAccountBalance', function(accountNo)
    local account = B.DB.single('SELECT balance FROM codex_bank_accounts WHERE account_no = ? OR job_name = ? LIMIT 1', { tostring(accountNo), tostring(accountNo) })
    return account and math.floor(tonumber(account.balance) or 0) or nil
end)

