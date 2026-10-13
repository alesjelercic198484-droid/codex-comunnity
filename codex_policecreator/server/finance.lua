--[[
    server/finance.lua - society funds, transaction log, bonuses and salaries.
]]

Finance = {}

local RESOURCE = GetCurrentResourceName()
local lastPayout = os.time()

local function log(message)
    if Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

--- Player pays into the department account.
function Finance.Deposit(src, amount)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if amount > 10000000 then return false, 'invalid_amount' end

    if not Bridge.RemoveMoney(src, amount, 'department-deposit') then
        return false, 'no_money'
    end

    local balance = Departments.AddFunds(member.deptId, amount, 'deposit',
        (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''), citizenid)

    if not balance then
        Bridge.AddMoney(src, amount, 'department-deposit-refund')
        return false, 'db'
    end

    Bridge.Notify(src, ('Deposited %s into the department account'):format(Core.FormatMoney(amount)), 'success')
    return true, balance
end

--- Cash out of the department account into the officer's bank.
function Finance.Withdraw(src, amount)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'finance') then return false, 'no_permission' end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if amount > dept.funds then return false, 'insufficient' end

    local balance = Departments.AddFunds(member.deptId, -amount, 'withdraw',
        (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''), citizenid)

    if not balance then return false, 'insufficient' end

    Bridge.AddMoney(src, amount, 'department-withdraw')
    Bridge.Notify(src, ('Withdrew %s from the department account'):format(Core.FormatMoney(amount)), 'success')
    return true, balance
end

--- One-off payment from the department account to a member.
function Finance.Bonus(src, targetCitizenid, amount)
    local citizenid = Bridge.GetIdentifier(src)
    local member = Members.Get(citizenid)
    if not member then return false, 'not_a_member' end

    local dept = Departments.Get(member.deptId)
    if not dept then return false, 'not_found' end
    if not Core.HasPerm(dept, member, 'finance') then return false, 'no_permission' end

    local target = Members.Get(targetCitizenid)
    if not target or target.deptId ~= member.deptId then return false, 'not_in_department' end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    if amount > dept.funds then return false, 'insufficient' end

    local balance = Departments.AddFunds(member.deptId, -amount, 'bonus',
        (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''), citizenid)

    if not balance then return false, 'insufficient' end

    local targetSrc = Members.OnlineSource(targetCitizenid)
    if targetSrc then
        Bridge.AddMoney(targetSrc, amount, 'department-bonus')
        Bridge.Notify(targetSrc, ('You received a %s bonus from %s'):format(Core.FormatMoney(amount), dept.label), 'success')
    end

    return true, balance
end

--- Pays every member of one department. Returns count, total.
function Finance.PayoutDepartment(deptId)
    local dept = Departments.Get(deptId)
    if not dept then return 0, 0 end

    local payOnlyOnDuty = Config.Duty and Config.Duty.PayOnlyOnDuty
    local paid = 0
    local total = 0

    for _, member in ipairs(Members.ListByDept(deptId)) do
        if not payOnlyOnDuty or member.onDuty then
            local amount = math.floor(tonumber(member.salary) or 0)
            if amount > 0 and dept.funds >= amount then
                local balance = Departments.AddFunds(deptId, -amount, 'salary',
                    (member.firstName .. ' ' .. member.lastName):gsub('%s+$', ''), member.citizenid)

                if balance then
                    -- re-read the cached department so the next iteration sees the new balance
                    dept = Departments.Get(deptId) or dept
                    paid = paid + 1
                    total = total + amount

                    local src = Members.OnlineSource(member.citizenid)
                    if src then
                        Bridge.AddMoney(src, amount, 'department-salary')
                        Bridge.Notify(src, ('Salary paid: %s from %s'):format(Core.FormatMoney(amount), dept.label), 'success')
                    end
                end
            end
        end
    end

    return paid, total
end

--- Called from the timer in main.lua.
function Finance.PayoutAll(force)
    local interval = math.floor((Config.Duty and Config.Duty.SalaryInterval or 600000) / 1000)
    if not force and (os.time() - lastPayout) < interval then return 0, 0 end

    lastPayout = os.time()

    local paid = 0
    local total = 0
    for id in pairs(Departments.All()) do
        local count, amount = Finance.PayoutDepartment(id)
        paid = paid + count
        total = total + amount
    end

    if paid > 0 then
        log(('salaries paid to %d members (%s)'):format(paid, Core.FormatMoney(total)))
    end
    return paid, total
end

function Finance.LastPayout()
    return lastPayout
end

function Finance.Logs(deptId, limit)
    local rows = Departments.FinanceLogs(deptId, limit)
    local out = {}

    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(row.id),
            citizenid = row.citizenid,
            name = row.name,
            type = row.type,
            amount = tonumber(row.amount) or 0,
            balance = tonumber(row.balance_after) or 0,
            timestamp = tonumber(row.timestamp) or 0,
            date = Core.FormatTimestamp(tonumber(row.timestamp) or 0)
        }
    end

    return out
end
