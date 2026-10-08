local B = CodexBanking
local QBCore = B.QBCore

local function logSystemTransaction(toAccountId, kind, amount, description)
    B.DB.insert([[
        INSERT INTO codex_bank_transactions
            (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description)
        VALUES (?, NULL, ?, 'system', ?, ?, 0, ?)
    ]], { B.MakeReference('SYS'), toAccountId, kind, amount, description })
end

local function recordOnlineMinute()
    for _, source in ipairs(QBCore.Functions.GetPlayers()) do
        local player = B.GetPlayer(source)
        local cid = B.GetCitizenId(player)
        if cid then
            B.DB.query([[
                INSERT INTO codex_bank_activity (citizenid, activity_day, online_seconds)
                VALUES (?, CURDATE(), 60)
                ON DUPLICATE KEY UPDATE online_seconds = online_seconds + 60
            ]], { cid })
        end
    end
end

local function processSavingsInterest()
    if not Config.Savings.Enabled then return end
    local accounts = B.DB.query([[
        SELECT * FROM codex_bank_accounts
        WHERE account_type = 'savings' AND (last_interest_day IS NULL OR last_interest_day < CURDATE())
        ORDER BY id ASC
    ]], {})

    for _, account in ipairs(accounts) do
        local cid = account.owner_cid
        local onlineSeconds = tonumber(B.DB.scalar([[
            SELECT online_seconds FROM codex_bank_activity
            WHERE citizenid = ? AND activity_day = CURDATE() LIMIT 1
        ]], { cid })) or 0
        local tier = Config.Savings.Tiers[tonumber(account.savings_tier) or 1] or Config.Savings.Tiers[1]
        local rate = tonumber(tier.interestPerPeriod) or 0
        local balance = math.floor(tonumber(account.balance) or 0)
        local interest = 0
        if onlineSeconds >= (tonumber(Config.Savings.RequiredOnlineSecondsPerDay) or 3600) and rate > 0 and balance > 0 then
            interest = math.min(math.floor(balance * rate), math.max(0, tonumber(account.max_balance) - balance))
        end

        local queries = {
            { query = 'UPDATE codex_bank_accounts SET balance = balance + ?, last_interest_day = CURDATE() WHERE id = ?', values = { interest, account.id } }
        }
        if interest > 0 then
            queries[#queries + 1] = {
                query = [[INSERT INTO codex_bank_transactions (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description) VALUES (?, NULL, ?, 'system', 'savings_interest', ?, 0, ?)]],
                values = { B.MakeReference('INT'), account.id, interest, ('Savings interest — %s'):format(tier.label or 'tier') }
            }
        end
        if B.DB.transaction(queries) and interest > 0 then
            B.SyncLegacy(cid)
        end
    end
end

local function seizeCollateral(loan)
    local plate = tostring(loan.collateral_plate or ''):upper()
    if plate == '' then return false end
    local tableName = tostring(Config.Loans.VehicleTable or 'player_vehicles')
    if not tableName:match('^[%w_]+$') then return false end
    local bankCid = tostring(Config.Loans.BankVehicleCitizenId or 'codex_bank')

    if B.DB.single('SELECT loan_id FROM codex_bank_repossessions WHERE loan_id = ? LIMIT 1', { loan.id }) then
        return true
    end

    local ok, vehicle = pcall(function()
        return B.DB.single(('SELECT citizenid FROM `%s` WHERE UPPER(plate) = ? LIMIT 1'):format(tableName), { plate })
    end)
    if not ok or not vehicle then return false end

    local currentOwner = tostring(vehicle.citizenid or '')
    if currentOwner ~= tostring(loan.borrower_cid) and currentOwner ~= bankCid then
        return false
    end

    local queries = {}
    if currentOwner == tostring(loan.borrower_cid) then
        queries[#queries + 1] = {
            query = ('UPDATE `%s` SET citizenid = ? WHERE citizenid = ? AND UPPER(plate) = ?'):format(tableName),
            values = { bankCid, loan.borrower_cid, plate }
        }
    end
    queries[#queries + 1] = {
        query = [[
            INSERT IGNORE INTO codex_bank_repossessions (loan_id, plate, previous_owner_cid, status)
            VALUES (?, ?, ?, 'repossessed')
        ]],
        values = { loan.id, plate, loan.borrower_cid }
    }

    if not B.DB.transaction(queries) then return false end
    local seizedVehicle = B.DB.single(('SELECT citizenid FROM `%s` WHERE UPPER(plate) = ? LIMIT 1'):format(tableName), { plate })
    if not seizedVehicle or tostring(seizedVehicle.citizenid or '') ~= bankCid then
        B.DB.update('DELETE FROM codex_bank_repossessions WHERE loan_id = ?', { loan.id })
        return false
    end
    return B.DB.single('SELECT loan_id FROM codex_bank_repossessions WHERE loan_id = ? LIMIT 1', { loan.id }) ~= nil
end

local function retryDefaultedRepossessions()
    if not Config.Loans.SeizeVehicleOnDefault then return end
    local loans = B.DB.query([[
        SELECT l.*
        FROM codex_bank_loans l
        LEFT JOIN codex_bank_repossessions r ON r.loan_id = l.id
        WHERE l.status = 'defaulted'
          AND l.collateral_plate IS NOT NULL
          AND l.collateral_plate <> ''
          AND r.loan_id IS NULL
        ORDER BY l.id ASC
    ]], {})
    for _, loan in ipairs(loans) do
        if not seizeCollateral(loan) and Config.Debug then
            print(('^3[codex_banking] Collateral vehicle %s is still unavailable for defaulted loan %s.^7'):format(loan.collateral_plate, loan.reference))
        end
    end
end

local function processLateLoans()
    if not Config.Loans.Enabled then return end
    local loans = B.DB.query([[
        SELECT * FROM codex_bank_loans
        WHERE status IN ('active', 'late') AND due_at < NOW()
          AND (last_penalty_at IS NULL OR DATE(last_penalty_at) < CURDATE())
        ORDER BY id ASC
    ]], {})

    for _, loan in ipairs(loans) do
        local balance = math.max(0, math.floor(tonumber(loan.balance) or 0))
        if balance > 0 then
            local penalty = math.max(1, math.floor(balance * (tonumber(Config.Loans.LatePenaltyPercentPerDay) or 0.01)))
            local lateDays = tonumber(B.DB.scalar('SELECT DATEDIFF(CURDATE(), DATE(?))', { loan.due_at })) or 0
            local shouldDefault = lateDays >= (tonumber(Config.Loans.DefaultAfterDaysLate) or 14)
            local nextBalance = balance + penalty
            local nextStatus = shouldDefault and 'defaulted' or 'late'
            local saved = B.DB.transaction({
                { query = 'UPDATE codex_bank_loans SET balance = ?, status = ?, last_penalty_at = NOW() WHERE id = ? AND status IN (\'active\', \'late\')', values = { nextBalance, nextStatus, loan.id } },
                { query = [[INSERT INTO codex_bank_transactions (reference, from_account_id, to_account_id, actor_cid, type, amount, fee, description) VALUES (?, NULL, NULL, 'system', 'loan_penalty', ?, 0, ?)]], values = { B.MakeReference('LATE'), penalty, ('Late loan fee — %s'):format(loan.reference) } }
            })
            if saved then
                B.AdjustCredit(loan.borrower_cid, shouldDefault and -75 or -10)
                if shouldDefault and loan.collateral_plate and Config.Loans.SeizeVehicleOnDefault then
                    if not seizeCollateral(loan) and Config.Debug then
                        print(('^3[codex_banking] Collateral vehicle %s could not be moved to the bank owner. Check Config.Loans.VehicleTable and your player_vehicles schema.^7'):format(loan.collateral_plate))
                    end
                end
            end
        end
    end
end

local function expirePaperwork()
    B.DB.update("UPDATE codex_bank_invoices SET status = 'expired' WHERE status = 'pending' AND due_at < NOW()", {})
    B.DB.update("UPDATE codex_bank_cheques SET status = 'expired' WHERE status = 'issued' AND expires_at < NOW()", {})
end

CreateThread(function()
    while not B.Ready do Wait(1000) end
    while true do
        Wait(60000)
        recordOnlineMinute()
        -- The interest and delinquency work is deliberately batched; the global
        -- financial lock prevents it racing a player transaction.
        B.WithLock(function()
            processSavingsInterest()
            processLateLoans()
            retryDefaultedRepossessions()
            expirePaperwork()
            return { ok = true }
        end)
    end
end)

