(function () {
  'use strict';

  var RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'codex_banking';
  var app = document.getElementById('app');
  var content = document.getElementById('content');
  var nav = document.getElementById('nav');
  var state = {
    visible: false,
    mode: 'bank',
    locale: 'en',
    currencySymbol: '$',
    token: null,
    page: 'overview',
    unlocked: false,
    data: null,
    atmCards: [],
    atmMeta: null,
    selectedCard: null,
    adminData: null,
    busy: false
  };

  var i18n = {
    en: {
      overview: 'Overview', accounts: 'Accounts', cards: 'Cards', savings: 'Savings', loans: 'Loans', invoices: 'Invoices', cheques: 'Cheques', safe: 'Safe boxes', company: 'Company', admin: 'Administration',
      personalBanking: 'Personal banking', adminLabel: 'Administration', secure: 'Secure connection', close: 'Close banking', network: 'Network online', allNetwork: 'CodeX Network', dashboardEyebrow: 'FINANCIAL OVERVIEW',
      hello: 'Welcome back', dashboardDesc: 'Your accounts and recent banking activity in one place.', totalPersonal: 'Personal funds', cash: 'Cash', coreBank: 'QBCore bank balance', credit: 'Credit score',
      checkingAccounts: 'Bank accounts', viewAll: 'All accounts', recent: 'Recent transactions', noTransactions: 'No transactions yet.', quickActions: 'Quick services', deposit: 'Deposit', depositDesc: 'Cash into account', withdraw: 'Withdraw', withdrawDesc: 'Cash from account', transfer: 'Transfer', transferDesc: 'Send to an account',
      account: 'Account', sourceAccount: 'From account', destination: 'IBAN / account number', amount: 'Amount', note: 'Transfer note', submitTransfer: 'Send transfer', amountPlaceholder: 'e.g. 2500', depositAmount: 'Cash to deposit', withdrawAmount: 'Cash withdrawal', submitDeposit: 'Deposit cash', submitWithdraw: 'Withdraw cash',
      atBranch: 'Branch service', atATM: 'ATM', atmWelcome: 'Insert your bank card', atmDesc: 'Select a card and enter its four-digit PIN to continue securely.', chooseCard: 'Select card', pin: 'Four-digit PIN', unlock: 'Verify PIN', noCards: 'You do not have an active ATM card.',
      card: 'Card', accountNo: 'Account number', checking: 'Personal account', savingsAccount: 'Savings account', shared: 'Shared account', companyAccount: 'Company account', balance: 'Balance', dailyLimit: 'Daily limit', level: 'Level', role: 'Role', accountList: 'Your accounts', accountIntro: 'Manage accounts and shared access.', openSavings: 'Open savings account', openShared: 'Create shared account', newAccount: 'Open account', tier: 'Savings tier',
      sharedName: 'Shared account name', create: 'Create', memberManagement: 'Member access', managedAccount: 'Shared account', chooseAccount: 'Select an account', citizenId: 'Citizen ID', accessRole: 'Role', roleAdmin: 'Admin', roleMember: 'Member', roleViewer: 'Read only', addMember: 'Add member', remove: 'Remove', upgrade: 'Upgrade account', goal: 'Savings goal', goalName: 'Goal name', saveGoal: 'Save goal', noAccounts: 'Visit a branch to set up a bank account.',
      cardsIntro: 'Manage cards, PINs and daily limits.', newCard: 'Order a new card', cardTier: 'Card tier', createCard: 'Issue card', cardPin: 'Set a four-digit PIN', freeze: 'Freeze', unfreeze: 'Unfreeze', frozen: 'Frozen', active: 'Active', noCardsPage: 'You do not have a bank card yet.', cardLimit: 'Card daily limit', holder: 'Cardholder', cardSecure: 'PINs are verified server-side and are never displayed after card issue.',
      savingsIntro: 'Savings earn daily interest when you are active for at least one hour per day.', savingsRate: 'Interest / period', savingsGoalProgress: 'Goal progress', interestNote: 'Interest is credited once daily after at least 60 minutes of play.', loanIntro: 'Choose a loan plan based on your credit score. Late payments lower your score and increase the balance.', plan: 'Loan plan', loanAmount: 'Loan amount', payoutAccount: 'Payout account', collateral: 'Collateral vehicle plate', apply: 'Apply for loan', due: 'Due date', outstanding: 'Outstanding', principal: 'Principal', pay: 'Repay', noLoans: 'You have no open loans.', securedNote: 'The secured plan requires a vehicle registered to you. Default may result in repossession.',
      invoiceIntro: 'Create a payment request or settle an invoice you received.', recipient: 'Recipient Citizen ID', reason: 'Reason / description', issueInvoice: 'Issue invoice', payInvoice: 'Pay', pending: 'Pending', paid: 'Paid', expired: 'Expired', issuedByYou: 'Issued by you', received: 'Received', noInvoices: 'No open invoices.', chequeIntro: 'Issue a bearer or named cheque. Cheques expire after seven days and can bounce if funds are unavailable.', issueCheque: 'Issue cheque', beneficiaryOptional: 'Beneficiary Citizen ID (optional)', chequeNumber: 'Cheque number', cashCheque: 'Cash cheque', receiveCash: 'Pay out as cash', depositCheque: 'Deposit to account', cancelCheque: 'Cancel', noCheques: 'No issued or received cheques.', chequeIssued: 'Issued cheque', bearer: 'Bearer', cashed: 'Cashed', bounced: 'Bounced', cancelled: 'Cancelled', defaulted: 'Defaulted',
      safeIntro: 'Rent a private safety deposit box at a branch. Contents are held in your inventory.', safeTier: 'Safe box size', rent: 'Rent / renew', openSafe: 'Open safe box', rentUntil: 'Rental expires', noSafe: 'You do not have a safe box.', safeNote: 'Visit the branch where your box is registered to open it.', companyIntro: 'Company account access depends on your job and grade.', noCompany: 'Your job does not have a CodeX company account enabled.',
      atmTitle: 'CodeX ATM', buyATM: 'Buy ATM', atmOwned: 'You own this ATM.', ownedByAnother: 'This ATM is owned by another player.', atmSurcharge: 'Surcharge (%)', saveSurcharge: 'Save surcharge', collectFees: 'Collect earnings', noATMOwner: 'This ATM is bank-owned.', ownerEarnings: 'Owner earnings', buyPrice: 'Purchase price', adminTitle: 'Management console', adminDesc: 'Banking-system overview and live economy settings.', refresh: 'Refresh', totalLedger: 'Total ledger balance', accountsCount: 'Accounts', todayVolume: 'Today volume', activeLoans: 'Open loans', loanExposure: 'Loan exposure', ownedATMs: 'Private ATMs', fees: 'Bank fee income', transferFee: 'Inter-bank fee (%)', saveSettings: 'Save settings', systemTransactions: 'Recent transactions', branchCount: 'Branches', noData: 'Data unavailable.', roleOwner: 'Owner', roleCompany: 'Company', transaction: 'Transaction', date: 'Date', status: 'Status', actions: 'Actions', empty: 'Nothing to display.', bankFee: 'Fee', helpBranch: 'Some services are available only at a branch.', atmOnly: 'ATMs support cash withdrawals and card services.',
      accountOpened: 'Bank account opened.', savingsOpened: 'Savings account opened.', sharedOpened: 'Shared account created.', memberAdded: 'Member access added.', memberRemoved: 'Member removed.', accountUpgraded: 'Account upgraded.', goalSaved: 'Savings goal saved.', cardCreated: 'Card issued.', cardFrozen: 'Card frozen.', cardUnfrozen: 'Card unlocked.', cardAccepted: 'Card accepted.', depositComplete: 'Deposit complete.', withdrawComplete: 'Withdrawal complete.', transferComplete: 'Transfer complete.', invoiceCreated: 'Invoice issued.', invoicePaid: 'Invoice paid.', chequeCreated: 'Cheque issued.', chequeCashed: 'Cheque cashed.', chequeCancelled: 'Cheque cancelled.', loanApproved: 'Loan approved.', loanPaymentComplete: 'Repayment recorded.', atmPurchased: 'You now own this ATM.', atmSurchargeSaved: 'Surcharge saved.', atmEarningsCollected: 'ATM earnings deposited.', safeBoxRented: 'Safe box rented or renewed.', safeBoxOpened: 'Safe box opened.', settingSaved: 'Setting saved.',
      errors: {
        not_ready: 'Banking is still loading.', not_authenticated: 'Player is not logged in.', no_permission: 'You are not authorized to do that.', admin_action_required: 'Use the admin console for this action.', too_far: 'You must be at a bank or ATM.', session_expired: 'Banking session expired. Reopen the interface.', server_error: 'Something went wrong.', busy: 'Banking is busy. Try again shortly.', invalid_bank: 'This bank is unavailable.', account_exists: 'This account already exists.', account_required: 'Open a personal checking account first.', opening_fee: 'Not enough money to pay the opening fee.', account_not_found: 'Account not found.', account_limit: 'You reached the account limit.', invalid_label: 'Name must be at least three characters.', invalid_amount: 'Enter a valid amount.', insufficient_funds: 'Not enough funds in the account.', insufficient_cash: 'Not enough cash.', destination_limit: 'The receiving account would exceed its balance limit.', invalid_destination: 'Enter a valid account number.', interbank_daily_cap: 'Daily inter-bank transfer cap reached.', daily_limit: 'Daily account limit reached.', card_daily_limit: 'Card daily limit reached.', invalid_tier: 'Invalid tier selected.', invalid_pin: 'PIN must be four digits.', wrong_pin: 'Incorrect PIN.', card_locked: 'Card temporarily locked.', card_frozen: 'Card is frozen.', card_not_found: 'Card not found.', card_limit: 'Maximum number of cards reached.', card_required: 'Insert and verify a valid card.', invalid_role: 'Invalid access role.', citizen_not_found: 'Recipient Citizen ID not found.', already_member: 'This person already has access.', member_limit: 'This account has reached its member limit.', cannot_remove_self: 'The account owner cannot be removed.', member_not_found: 'Member not found.', max_level: 'Account is already at its highest level.', personal_checking_required: 'A personal checking account is required.', personal_account_required: 'Your own personal account is required.', branch_only: 'This service is available at a bank branch only.', feature_disabled: 'This service is disabled.', no_atm_earnings: 'This ATM has no earnings to collect.', atm_owned: 'This ATM is already owned.', invalid_reason: 'Enter a description.', invoice_not_found: 'Invoice not found or already paid.', invoice_expired: 'Payment deadline has passed.', cheque_not_found: 'Cheque not found.', cheque_not_for_you: 'This cheque is not payable to you.', cheque_expired: 'Cheque has expired.', cheque_bounced: 'Cheque bounced because the issuer has insufficient funds.', loan_not_found: 'Loan not found.', invalid_loan_plan: 'Loan plan unavailable.', credit_score_low: 'Credit score is too low for this plan.', loan_limit: 'Maximum number of open loans reached.', wrong_loan_account: 'This account cannot receive this loan.', collateral_required: 'Enter the plate of a vehicle to use as collateral.', vehicle_not_owned: 'That vehicle is not registered to you.', vehicle_pledged: 'That vehicle is already pledged.', safe_box_not_found: 'Safe box not found.', safe_box_expired: 'Safe-box rental expired.', inventory_unavailable: 'Start ox_inventory or qb-inventory to use safe boxes.', no_permission_admin: 'You are not authorized to use the admin console.', invalid_setting: 'Invalid setting value.', unknown_action: 'Unknown action.', slow_down: 'Please wait a moment and try again.'
      }
    }
  };

  var navItems = [
    { id: 'overview', icon: '◫', key: 'overview' },
    { id: 'accounts', icon: '▤', key: 'accounts' },
    { id: 'cards', icon: '▱', key: 'cards' },
    { id: 'savings', icon: '◉', key: 'savings' },
    { id: 'loans', icon: '↗', key: 'loans' },
    { id: 'invoices', icon: '▧', key: 'invoices' },
    { id: 'cheques', icon: '▱', key: 'cheques' },
    { id: 'safe', icon: '▣', key: 'safe' },
    { id: 'company', icon: '⌂', key: 'company' }
  ];

  function t(key) {
    var locale = i18n.en;
    if (Object.prototype.hasOwnProperty.call(locale, key)) return locale[key];
    return key;
  }

  function errorText(key) {
    var locale = i18n.en;
    return (locale.errors && locale.errors[key]) || key || t('noData');
  }

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function (character) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
    });
  }

  function money(value) {
    var amount = Number(value) || 0;
    return (amount < 0 ? '-' : '') + String(state.currencySymbol || '$') + Math.abs(Math.round(amount)).toLocaleString('en-US');
  }

  function dateLabel(value) {
    if (!value) return '—';
    var normalized = String(value).replace(' ', 'T');
    var date = new Date(normalized);
    if (isNaN(date.getTime())) return esc(value);
    return new Intl.DateTimeFormat('en-US', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(date);
  }

  function post(endpoint, payload) {
    return fetch('https://' + RESOURCE + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {})
    }).then(function (response) { return response.json(); }).catch(function () { return { ok: false, message: 'server_error' }; });
  }

  var messageAliases = {
    account_opened: 'accountOpened', savings_opened: 'savingsOpened', shared_opened: 'sharedOpened',
    member_added: 'memberAdded', member_removed: 'memberRemoved', account_upgraded: 'accountUpgraded',
    goal_saved: 'goalSaved', card_created: 'cardCreated', card_frozen: 'cardFrozen', card_unfrozen: 'cardUnfrozen',
    card_accepted: 'cardAccepted', deposit_complete: 'depositComplete', withdraw_complete: 'withdrawComplete',
    transfer_complete: 'transferComplete', invoice_created: 'invoiceCreated', invoice_paid: 'invoicePaid',
    cheque_created: 'chequeCreated', cheque_cashed: 'chequeCashed', cheque_cancelled: 'chequeCancelled',
    loan_approved: 'loanApproved', loan_payment_complete: 'loanPaymentComplete', atm_purchased: 'atmPurchased',
    atm_surcharge_saved: 'atmSurchargeSaved', atm_earnings_collected: 'atmEarningsCollected',
    safe_box_rented: 'safeBoxRented', safe_box_opened: 'safeBoxOpened', setting_saved: 'settingSaved'
  };

  function toast(message, kind) {
    var stack = document.getElementById('toast-stack');
    if (!stack) return;
    var item = document.createElement('div');
    item.className = 'toast ' + (kind || 'success');
    var key = messageAliases[message] || message;
    item.textContent = i18n.en[key] ? i18n.en[key] : errorText(message);
    stack.appendChild(item);
    window.setTimeout(function () { item.remove(); }, 3400);
  }

  function close() { post('close', {}); }

  function accounts() { return state.data && Array.isArray(state.data.accounts) ? state.data.accounts : []; }
  function cards() { return state.data && Array.isArray(state.data.cards) ? state.data.cards : []; }

  function accountTitle(account) {
    if (account.type === 'checking') return t('checking');
    if (account.type === 'savings') return t('savingsAccount');
    if (account.type === 'shared') return t('shared');
    if (account.type === 'company') return t('companyAccount');
    return esc(account.type);
  }

  function accountOptions(filter, selected) {
    return accounts().filter(filter || function () { return true; }).map(function (account) {
      var isSelected = String(account.id) === String(selected) ? ' selected' : '';
      return '<option value="' + esc(account.id) + '"' + isSelected + '>' + esc(account.label) + ' · ' + money(account.balance) + '</option>';
    }).join('');
  }

  function personalAccounts() {
    return accounts().filter(function (account) { return account.type === 'checking' && account.isPersonal !== false; });
  }

  function pageHead(eyebrow, title, description, actions) {
    return '<div class="page-head"><div><div class="eyebrow">' + esc(eyebrow) + '</div><h1>' + esc(title) + '</h1><p>' + esc(description || '') + '</p></div><div class="head-actions">' + (actions || '') + '</div></div>';
  }

  function statCard(label, value, icon, foot) {
    return '<div class="stat-card"><div class="stat-top"><span>' + esc(label) + '</span><span class="stat-icon">' + esc(icon) + '</span></div><div class="stat-value">' + esc(value) + '</div><div class="stat-foot">' + esc(foot || '') + '</div></div>';
  }

  function emptyState(text, icon) {
    return '<div class="empty-state"><div class="empty-icon">' + esc(icon || '◌') + '</div>' + esc(text || t('empty')) + '</div>';
  }

  function renderNav() {
    var list;
    if (state.mode === 'admin') {
      list = [{ id: 'admin', icon: '⌘', key: 'admin' }];
      document.getElementById('nav-label').textContent = t('adminLabel');
    } else if (state.mode === 'atm') {
      list = [{ id: 'overview', icon: '◫', key: 'overview' }, { id: 'cards', icon: '▱', key: 'cards' }];
      document.getElementById('nav-label').textContent = t('atATM');
    } else {
      list = navItems;
      document.getElementById('nav-label').textContent = t('personalBanking');
    }
    nav.innerHTML = list.map(function (item) {
      return '<button type="button" data-page="' + item.id + '" class="' + (state.page === item.id ? 'active' : '') + '"><span class="nav-icon">' + item.icon + '</span><span class="nav-text">' + esc(t(item.key)) + '</span></button>';
    }).join('');
  }

  function transactionRow(tx, options) {
    options = options || {};
    var accountIds = options.accountIds || [];
    var fromId = Number(tx.from_account_id) || 0;
    var toId = Number(tx.to_account_id) || 0;
    var outgoing = accountIds.length ? accountIds.indexOf(fromId) !== -1 : false;
    var incoming = accountIds.length ? accountIds.indexOf(toId) !== -1 : !outgoing;
    var amount = Number(tx.amount) || 0;
    var signed = outgoing ? -amount : amount;
    var title = tx.description || tx.type || t('transaction');
    var icon = outgoing ? '↗' : '↙';
    var amountClass = outgoing ? 'negative' : 'positive';
    if (options.admin) {
      signed = amount;
      amountClass = 'muted';
      icon = '↔';
    }
    return '<div class="transaction"><div class="tx-icon">' + icon + '</div><div class="tx-main"><strong>' + esc(title) + '</strong><span>' + esc(tx.reference || tx.type || '') + ' · ' + dateLabel(tx.created_at) + '</span></div><div class="tx-amount ' + amountClass + '">' + (signed > 0 ? '+' : '') + money(signed) + (Number(tx.fee) ? '<small class="muted">' + t('bankFee') + ' ' + money(tx.fee) + '</small>' : '') + '</div></div>';
  }

  function accountCard(account, compact) {
    var role = account.role === 'owner' ? t('roleOwner') : (account.type === 'company' ? t('roleCompany') : esc(account.role));
    var actions = '';
    if (state.mode === 'atm' && state.data.session && state.data.session.mode === 'atm') {
      var activeCard = (state.data.cards || []).find(function (card) { return String(card.id) === String(state.data.session.cardId); });
      var configuredMax = Number(state.data.limits && state.data.limits.maxAmount) || 10000000;
      var cardRemaining = activeCard ? Number(activeCard.daily_remaining) : 500000;
      var withdrawalMax = Math.max(0, Math.min(configuredMax, Number.isFinite(cardRemaining) ? cardRemaining : 0, Number(account.balance) || 0));
      actions = '<form class="form-grid" data-form="withdraw"><input type="hidden" name="accountId" value="' + esc(account.id) + '"><div class="field full"><label>' + t('withdrawAmount') + '</label><input name="amount" type="number" min="1" step="1" max="' + esc(withdrawalMax) + '" placeholder="250" required></div><div class="form-actions field full"><button class="btn" type="submit">' + t('submitWithdraw') + '</button></div></form>';
    } else if (state.mode !== 'atm' && account.canManage && account.level < 3) {
      actions = '<div class="form-actions"><button class="btn secondary small" data-action="upgradeAccount" data-account="' + esc(account.id) + '">' + t('upgrade') + '</button></div>';
    }
    return '<article class="account-card" style="--account-accent:' + esc(account.bankColor || '#54d7bd') + '"><div class="account-card-head"><div><div class="account-title">' + esc(account.label) + '</div><div class="account-type">' + esc(account.bankLabel || '') + ' · ' + accountTitle(account) + '</div></div><span class="badge ' + (account.type === 'company' ? 'gold' : '') + '">' + esc(role) + '</span></div><div class="account-balance">' + money(account.balance) + '</div><div class="account-number mono">' + esc(account.accountNo) + '</div><div class="account-meta"><span>' + t('dailyLimit') + ': ' + money(account.dailyLimit) + '</span><span>LVL ' + esc(account.level) + '</span></div>' + (actions || '') + '</article>';
  }

  function renderOverview() {
    var data = state.data || {};
    var total = accounts().filter(function (account) { return account.type === 'checking' || account.type === 'savings'; }).reduce(function (sum, account) { return sum + (Number(account.balance) || 0); }, 0);
    var txs = (data.transactions || []).slice(0, 6);
    var accountIds = accounts().map(function (account) { return Number(account.id); });
    var atmMode = state.mode === 'atm';
    var atmSection = '';
    if (atmMode && data.session && data.session.mode === 'atm') {
      var account = accounts()[0];
      var atmOwner = state.atmMeta || {};
      var isOwner = atmOwner.isOwner === true;
      var ownerStatus = isOwner ? t('atmOwned') : (atmOwner.isOwned ? t('ownedByAnother') : t('noATMOwner'));
      atmSection = '<div class="panel" style="margin-top:14px"><div class="panel-head"><h3>⌂ ' + t('atmTitle') + '</h3><small>' + ownerStatus + '</small></div>';
      if (isOwner) {
        atmSection += '<div class="split-panels"><div><div class="stat-top">' + t('ownerEarnings') + '</div><div class="stat-value">' + money(atmOwner.fee_balance || 0) + '</div><button class="btn small" data-action="collectATM" data-account="' + esc(account && account.id || '') + '">' + t('collectFees') + '</button></div><form data-form="atm-surcharge"><div class="field"><label>' + t('atmSurcharge') + '</label><input name="percent" type="number" min="0" max="3" step="0.1" value="' + esc(atmOwner.surcharge_percent || 0) + '"></div><div class="form-actions"><button class="btn small" type="submit">' + t('saveSurcharge') + '</button></div></form></div>';
      } else if (atmOwner.isOwned) {
        atmSection += '<div class="note-box">' + t('ownedByAnother') + '</div>';
      } else {
        atmSection += '<p class="form-note">' + t('buyPrice') + ': ' + money(atmOwner.price || 250000) + '</p><button class="btn" data-action="buyATM" data-account="' + esc(account && account.id || '') + '">' + t('buyATM') + '</button>';
      }
      atmSection += '</div>';
    }
    return pageHead(t('dashboardEyebrow'), t('hello') + ', ' + ((data.user && data.user.name) || ''), atmMode ? t('atmOnly') : t('dashboardDesc'), '<div class="credit-score"><span>' + t('credit') + '</span><b>' + esc(data.creditScore || 650) + '</b></div>') +
      '<div class="stats-grid">' + statCard(t('totalPersonal'), money(total), '◈', t('checkingAccounts')) + statCard(t('cash'), money(data.cash), '＄', '') + statCard(t('coreBank'), money(data.legacyBank), '▤', 'QBCore legacy sync') + statCard(t('credit'), String(data.creditScore || 650) + ' / 850', '✦', '300 — 850') + '</div>' +
      '<div class="layout-two"><section class="panel"><div class="panel-head"><h3>' + t('checkingAccounts') + '</h3><button class="btn-link" data-page="accounts">' + t('viewAll') + ' →</button></div><div class="account-grid">' + (accounts().length ? accounts().slice(0, 4).map(function (account) { return accountCard(account, true); }).join('') : emptyState(t('noAccounts'))) + '</div></section>' +
      '<section class="panel"><div class="panel-head"><h3>' + (atmMode ? t('atATM') : t('quickActions')) + '</h3><small>' + (atmMode ? t('atmOnly') : t('atBranch')) + '</small></div>' +
      (atmMode ? '<div class="note-box">' + t('atmOnly') + '</div>' : '<div class="quick-actions"><button class="quick-action" data-page="accounts"><span>＋</span><b>' + t('deposit') + '</b><small>' + t('depositDesc') + '</small></button><button class="quick-action" data-page="accounts"><span>↘</span><b>' + t('withdraw') + '</b><small>' + t('withdrawDesc') + '</small></button><button class="quick-action" data-page="accounts"><span>↗</span><b>' + t('transfer') + '</b><small>' + t('transferDesc') + '</small></button></div>') + '</section></div>' +
      atmSection +
      '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('recent') + '</h3><small>' + txs.length + ' / 30</small></div><div class="activity-list">' + (txs.length ? txs.map(function (tx) { return transactionRow(tx, { accountIds: accountIds }); }).join('') : emptyState(t('noTransactions'))) + '</div></section>';
  }

  function renderAccounts() {
    var data = state.data || {};
    var branchOnly = state.mode !== 'atm';
    var checkingOptions = accountOptions(function (account) { return account.type === 'checking' && account.canWithdraw; });
    var transferableOptions = accountOptions(function (account) { return account.canTransfer; });
    var accountCards = accounts().map(function (account) { return accountCard(account, false); }).join('');
    var forms = '';
    if (branchOnly) {
      forms = '<div class="split-panels" style="margin-top:14px">' +
        '<section class="panel"><div class="panel-head"><h3>↘ ' + t('deposit') + '</h3><small>' + t('depositDesc') + '</small></div><form data-form="deposit" class="form-grid"><div class="field full"><label>' + t('account') + '</label><select name="accountId" required>' + accountOptions(function (account) { return account.canWithdraw || account.role === 'viewer'; }) + '</select></div><div class="field full"><label>' + t('depositAmount') + '</label><input name="amount" type="number" min="1" step="1" required></div><div class="form-actions field full"><button class="btn" type="submit">' + t('submitDeposit') + '</button></div></form></section>' +
        '<section class="panel"><div class="panel-head"><h3>↗ ' + t('withdraw') + '</h3><small>' + t('withdrawDesc') + '</small></div><form data-form="withdraw" class="form-grid"><div class="field full"><label>' + t('account') + '</label><select name="accountId" required>' + accountOptions(function (account) { return account.canWithdraw; }) + '</select></div><div class="field full"><label>' + t('withdrawAmount') + '</label><input name="amount" type="number" min="1" step="1" required></div><div class="form-actions field full"><button class="btn" type="submit">' + t('submitWithdraw') + '</button></div></form></section></div>' +
        '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>↔ ' + t('transfer') + '</h3><small>' + t('transferDesc') + '</small></div><form data-form="transfer" class="form-grid"><div class="field"><label>' + t('sourceAccount') + '</label><select name="accountId" required>' + transferableOptions + '</select></div><div class="field"><label>' + t('destination') + '</label><input name="destination" maxlength="32" required></div><div class="field"><label>' + t('amount') + '</label><input name="amount" type="number" min="1" step="1" required></div><div class="field"><label>' + t('note') + '</label><input name="description" maxlength="100"></div><div class="form-actions field full"><button class="btn" type="submit">' + t('submitTransfer') + '</button></div><div class="form-note field full">' + t('helpBranch') + '</div></form></section>' +
        '<div class="split-panels" style="margin-top:14px">' +
        '<section class="panel"><div class="panel-head"><h3>' + t('openSavings') + '</h3></div><form data-form="open-savings" class="form-grid"><div class="field full"><label>' + t('tier') + '</label><select name="tier">' + tierOptions(data.savingsTiers || {}) + '</select></div><div class="form-actions field full"><button class="btn" type="submit">' + t('openSavings') + '</button></div></form></section>' +
        '<section class="panel"><div class="panel-head"><h3>' + t('openShared') + '</h3></div><form data-form="open-shared" class="form-grid"><div class="field full"><label>' + t('sharedName') + '</label><input name="label" maxlength="48" required></div><div class="form-actions field full"><button class="btn" type="submit">' + t('create') + '</button></div></form></section></div>' +
        renderSharedManagement();
    }
    return pageHead(t('accountList'), t('accounts'), t('accountIntro')) +
      '<section class="panel"><div class="account-grid">' + (accountCards || emptyState(t('noAccounts'))) + '</div></section>' + forms;
  }

  function tierOptions(tiers) {
    return Object.keys(tiers).sort(function (a, b) { return Number(a) - Number(b); }).map(function (key) {
      var tier = tiers[key] || {};
      var rate = (Number(tier.interestPerPeriod) * 100 || 0).toFixed(2);
      return '<option value="' + esc(key) + '">' + esc(tier.label || ('Tier ' + key)) + ' · ' + rate + '%</option>';
    }).join('');
  }

  function renderSharedManagement() {
    var shared = accounts().filter(function (account) { return account.type === 'shared' && account.canManage; });
    if (!shared.length) return '';
    var memberRows = shared.map(function (account) {
      return (account.members || []).map(function (member) {
        var roleLabel = member.role === 'owner' ? t('roleOwner') : (member.role === 'admin' ? t('roleAdmin') : (member.role === 'viewer' ? t('roleViewer') : t('roleMember')));
        return '<tr><td><strong>' + esc(member.citizenid) + '</strong><small>' + esc(account.label) + ' · ' + esc(account.accountNo) + '</small></td><td>' + esc(roleLabel) + '</td><td>' + (member.role === 'owner' ? '—' : '<button class="btn danger small" data-action="removeMember" data-account="' + esc(account.id) + '" data-citizen="' + esc(member.citizenid) + '">' + t('remove') + '</button>') + '</td></tr>';
      }).join('');
    }).join('');
    return '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('memberManagement') + '</h3><small>' + t('managedAccount') + '</small></div><form data-form="add-member" class="form-grid"><div class="field"><label>' + t('chooseAccount') + '</label><select name="accountId" required>' + accountOptions(function (account) { return account.type === 'shared' && account.canManage; }) + '</select></div><div class="field"><label>' + t('citizenId') + '</label><input name="citizenid" maxlength="64" required></div><div class="field"><label>' + t('accessRole') + '</label><select name="role"><option value="member">' + t('roleMember') + '</option><option value="admin">' + t('roleAdmin') + '</option><option value="viewer">' + t('roleViewer') + '</option></select></div><div class="form-actions"><button class="btn" type="submit">' + t('addMember') + '</button></div></form>' + (memberRows ? '<div class="table-wrap" style="margin-top:14px"><table class="data-table"><thead><tr><th>' + t('citizenId') + '</th><th>' + t('role') + '</th><th>' + t('actions') + '</th></tr></thead><tbody>' + memberRows + '</tbody></table></div>' : '') + '</section>';
  }

  function renderCards() {
    var data = state.data || {};
    var isAtmUnlocked = state.mode === 'atm' && data.session && data.session.mode === 'atm';
    var list = cards().map(function (card) {
      var tier = String(card.tier_label || card.tier || 'Standard');
      var freezeButton = isAtmUnlocked ? '' : '<button class="btn small ' + (card.frozen ? 'secondary' : 'danger') + '" data-action="freezeCard" data-card="' + esc(card.id) + '" data-frozen="' + (card.frozen ? '0' : '1') + '">' + t(card.frozen ? 'unfreeze' : 'freeze') + '</button>';
      return '<div class="panel"><div class="card-visual" style="--card-color:' + esc(card.color || '#54d7bd') + '"><div class="account-card-head"><strong>' + esc(tier) + '</strong><span class="badge ' + (card.frozen ? 'red' : 'gold') + '">' + t(card.frozen ? 'frozen' : 'active') + '</span></div><div class="card-chip"></div><div class="card-bottom"><div class="card-number">•••• &nbsp;•••• &nbsp;•••• &nbsp;' + esc(card.last4) + '</div><div class="card-holder"><b>' + esc((data.user && data.user.name) || '') + '</b></div></div></div><div class="account-meta"><span>' + esc(card.account_no || '') + '</span><span>' + t('cardLimit') + ': ' + money(card.daily_limit) + '</span></div><div class="form-actions">' + freezeButton + '</div></div>';
    }).join('');
    var form = '';
    if (!isAtmUnlocked) {
      form = '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('newCard') + '</h3></div><form data-form="create-card" class="form-grid"><div class="field"><label>' + t('account') + '</label><select name="accountId" required>' + accountOptions(function (account) { return account.canManage; }) + '</select></div><div class="field"><label>' + t('cardTier') + '</label><select name="tier">' + cardTierOptions(data.cardTiers || {}) + '</select></div><div class="field"><label>' + t('cardPin') + '</label><input name="pin" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" required></div><div class="field" style="align-self:end"><button class="btn" type="submit">' + t('createCard') + '</button></div></form><div class="form-note">' + t('cardSecure') + '</div></section>';
    }
    return pageHead(t('cardsIntro'), t('cards'), t('cardsIntro')) +
      (isAtmUnlocked ? '<div class="note-box" style="margin-bottom:13px">' + t('atmOnly') + '</div>' : '') +
      (list ? '<div class="split-panels">' + list + '</div>' : emptyState(t('noCardsPage'), '▱')) + form;
  }

  function cardTierOptions(tiers) {
    return Object.keys(tiers).map(function (key) {
      var tier = tiers[key] || {};
      return '<option value="' + esc(key) + '">' + esc(tier.label || key) + ' · ' + money(tier.issueCost || 0) + '</option>';
    }).join('');
  }

  function renderSavings() {
    var savings = accounts().filter(function (account) { return account.type === 'savings'; });
    var cardsHtml = savings.map(function (account) {
      var tier = (state.data.savingsTiers || {})[account.savingsTier] || {};
      var rate = (Number(tier.interestPerPeriod) * 100 || 0).toFixed(2);
      var goal = Number(account.savingsGoal) || 0;
      var pct = goal > 0 ? Math.max(0, Math.min(100, Number(account.balance) / goal * 100)) : 0;
      return '<article class="account-card" style="--account-accent:#d7b969"><div class="account-card-head"><div><div class="account-title">' + esc(account.label) + '</div><div class="account-type">' + esc(account.bankLabel) + ' · ' + esc(tier.label || t('savingsAccount')) + '</div></div><span class="badge gold">' + rate + '%</span></div><div class="account-balance">' + money(account.balance) + '</div><div class="progress"><i style="width:' + pct.toFixed(1) + '%"></i></div><div class="account-meta"><span>' + (account.savingsGoalLabel ? esc(account.savingsGoalLabel) : t('goal')) + '</span><span>' + (goal ? money(goal) : '—') + '</span></div><form data-form="savings-goal" class="form-grid" style="margin-top:10px"><input type="hidden" name="accountId" value="' + esc(account.id) + '"><div class="field"><label>' + t('goalName') + '</label><input name="label" value="' + esc(account.savingsGoalLabel || '') + '" maxlength="64"></div><div class="field"><label>' + t('goal') + '</label><input name="amount" type="number" min="0" value="' + goal + '"></div><div class="form-actions field full"><button class="btn small" type="submit">' + t('saveGoal') + '</button></div></form></article>';
    }).join('');
    return pageHead(t('savingsIntro'), t('savings'), t('savingsIntro')) +
      '<div class="note-box" style="margin-bottom:14px">' + t('interestNote') + '</div>' +
      (cardsHtml ? '<div class="account-grid">' + cardsHtml + '</div>' : emptyState(t('noAccounts'), '◉'));
  }

  function renderLoans() {
    var data = state.data || {};
    var plans = data.plans || {};
    var loanRows = data.loans || [];
    var options = Object.keys(plans).map(function (key) {
      var plan = plans[key];
      return '<option value="' + esc(key) + '">' + esc(plan.label || key) + ' · max ' + money(plan.maxAmount || 0) + ' · ' + ((Number(plan.annualRate) * 100) || 0).toFixed(1) + '% APR</option>';
    }).join('');
    var loanCards = loanRows.map(function (loan) {
      var status = loan.status === 'late' ? '<span class="badge red">' + esc(loan.status) + '</span>' : (loan.status === 'paid' ? '<span class="badge">' + t('paid') + '</span>' : '<span class="badge gold">' + esc(loan.status) + '</span>');
      return '<tr><td><strong>' + esc(loan.reference) + '</strong><small>' + esc(loan.plan_id) + (loan.collateral_plate ? ' · ' + esc(loan.collateral_plate) : '') + '</small></td><td>' + money(loan.principal) + '</td><td><strong>' + money(loan.balance) + '</strong></td><td>' + dateLabel(loan.due_at) + '</td><td>' + status + '</td><td>' + (loan.status === 'active' || loan.status === 'late' || loan.status === 'defaulted' ? '<form data-form="loan-pay" class="inline-actions"><input type="hidden" name="loanId" value="' + esc(loan.id) + '"><select name="accountId" class="mini-select">' + accountOptions(function (account) { return account.canWithdraw; }) + '</select><input name="amount" type="number" min="1" max="' + esc(loan.balance) + '" placeholder="' + t('amount') + '" required><button class="btn small" type="submit">' + t('pay') + '</button></form>' : '—') + '</td></tr>';
    }).join('');
    return pageHead(t('loanIntro'), t('loans'), t('loanIntro')) +
      '<div class="note-box" style="margin-bottom:14px">' + t('securedNote') + '</div>' +
      '<section class="panel"><div class="panel-head"><h3>' + t('apply') + '</h3><span class="credit-score"><span>' + t('credit') + '</span><b>' + esc(data.creditScore || 650) + '</b></span></div><form data-form="loan-apply" class="form-grid"><div class="field"><label>' + t('plan') + '</label><select name="planId">' + options + '</select></div><div class="field"><label>' + t('payoutAccount') + '</label><select name="accountId" required>' + accountOptions(function (account) { return account.type === 'checking' || account.type === 'company'; }) + '</select></div><div class="field"><label>' + t('loanAmount') + '</label><input name="amount" type="number" min="1" step="1" required></div><div class="field"><label>' + t('collateral') + '</label><input name="collateralPlate" maxlength="16"></div><div class="form-actions field full"><button class="btn" type="submit">' + t('apply') + '</button></div></form></section>' +
      '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('outstanding') + '</h3><small>' + loanRows.length + '</small></div>' + (loanRows.length ? '<div class="table-wrap"><table class="data-table"><thead><tr><th>' + t('transaction') + '</th><th>' + t('principal') + '</th><th>' + t('outstanding') + '</th><th>' + t('due') + '</th><th>' + t('status') + '</th><th>' + t('actions') + '</th></tr></thead><tbody>' + loanCards + '</tbody></table></div>' : emptyState(t('noLoans'))) + '</section>';
  }

  function renderInvoices() {
    var data = state.data || {};
    var maxAmount = Number(data.limits && data.limits.invoiceMaxAmount) || 1000000;
    var items = data.invoices || [];
    var rows = items.map(function (invoice) {
      var recipient = invoice.is_recipient;
      var status = invoice.status === 'paid' ? t('paid') : (invoice.status === 'expired' ? t('expired') : t('pending'));
      var actions = recipient && invoice.status === 'pending' ? '<form data-form="invoice-pay" class="inline-actions"><input type="hidden" name="invoiceId" value="' + esc(invoice.id) + '"><select name="accountId">' + accountOptions(function (account) { return account.canTransfer; }) + '</select><button class="btn small" type="submit">' + t('payInvoice') + '</button></form>' : (invoice.issuer_cid === data.user.citizenid && invoice.status === 'pending' ? '<span class="muted">' + t('issuedByYou') + '</span>' : '—');
      return '<tr><td><strong>' + esc(invoice.reason || invoice.reference) + '</strong><small>' + esc(invoice.reference) + ' · ' + (recipient ? t('received') : t('issuedByYou')) + '</small></td><td>' + money(invoice.amount) + '</td><td>' + dateLabel(invoice.due_at) + '</td><td>' + esc(status) + '</td><td>' + actions + '</td></tr>';
    }).join('');
    return pageHead(t('invoiceIntro'), t('invoices'), t('invoiceIntro')) +
      '<section class="panel"><div class="panel-head"><h3>' + t('issueInvoice') + '</h3></div><form data-form="invoice-create" class="form-grid"><div class="field"><label>' + t('sourceAccount') + '</label><select name="accountId">' + accountOptions(function (account) { return account.canManage; }) + '</select></div><div class="field"><label>' + t('recipient') + '</label><input name="recipientCid" maxlength="64" required></div><div class="field"><label>' + t('amount') + '</label><input name="amount" type="number" min="1" max="' + esc(maxAmount) + '" required></div><div class="field"><label>' + t('reason') + '</label><input name="reason" maxlength="100" required></div><div class="form-actions field full"><button class="btn" type="submit">' + t('issueInvoice') + '</button></div></form></section>' +
      '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('invoices') + '</h3></div>' + (rows ? '<div class="table-wrap"><table class="data-table"><thead><tr><th>' + t('reason') + '</th><th>' + t('amount') + '</th><th>' + t('due') + '</th><th>' + t('status') + '</th><th>' + t('actions') + '</th></tr></thead><tbody>' + rows + '</tbody></table></div>' : emptyState(t('noInvoices'))) + '</section>';
  }

  function renderCheques() {
    var data = state.data || {};
    var maxAmount = Number(data.limits && data.limits.chequeMaxAmount) || 1000000;
    var cheques = data.cheques || [];
    var rows = cheques.map(function (cheque) {
      var status = cheque.status === 'issued' ? t('pending') : (t(cheque.status) || esc(cheque.status));
      var action = cheque.issuer_cid === data.user.citizenid && cheque.status === 'issued' ? '<button class="btn danger small" data-action="cancelCheque" data-cheque="' + esc(cheque.id) + '">' + t('cancelCheque') + '</button>' : '—';
      return '<tr><td><strong class="mono">' + esc(cheque.cheque_no) + '</strong><small>' + esc(cheque.reason || t('chequeIssued')) + '</small></td><td>' + money(cheque.amount) + '</td><td>' + dateLabel(cheque.expires_at) + '</td><td>' + esc(status) + '</td><td>' + action + '</td></tr>';
    }).join('');
    return pageHead(t('chequeIntro'), t('cheques'), t('chequeIntro')) +
      '<div class="split-panels"><section class="panel"><div class="panel-head"><h3>' + t('issueCheque') + '</h3></div><form data-form="cheque-create" class="form-grid"><div class="field full"><label>' + t('sourceAccount') + '</label><select name="accountId">' + accountOptions(function (account) { return account.canWithdraw; }) + '</select></div><div class="field"><label>' + t('amount') + '</label><input name="amount" type="number" min="1" max="' + esc(maxAmount) + '" required></div><div class="field"><label>' + t('beneficiaryOptional') + '</label><input name="beneficiaryCid" maxlength="64"></div><div class="field full"><label>' + t('reason') + '</label><input name="reason" maxlength="100"></div><div class="form-actions field full"><button class="btn" type="submit">' + t('issueCheque') + '</button></div></form></section>' +
      '<section class="panel"><div class="panel-head"><h3>' + t('cashCheque') + '</h3></div><form data-form="cheque-cash" class="form-grid"><div class="field full"><label>' + t('chequeNumber') + '</label><input name="chequeNo" maxlength="16" required></div><div class="field full"><label>' + t('depositCheque') + '</label><select name="accountId"><option value="">' + t('receiveCash') + '</option>' + accountOptions(function (account) { return account.type === 'checking' || account.type === 'savings'; }) + '</select></div><div class="form-actions field full"><button class="btn" type="submit">' + t('cashCheque') + '</button></div></form></section></div>' +
      '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('cheques') + '</h3></div>' + (rows ? '<div class="table-wrap"><table class="data-table"><thead><tr><th>' + t('chequeNumber') + '</th><th>' + t('amount') + '</th><th>' + t('due') + '</th><th>' + t('status') + '</th><th>' + t('actions') + '</th></tr></thead><tbody>' + rows + '</tbody></table></div>' : emptyState(t('noCheques'))) + '</section>';
  }

  function renderSafeBoxes() {
    var data = state.data || {};
    var safeBoxes = data.safeBoxes || [];
    var rows = safeBoxes.map(function (box) {
      return '<div class="account-card"><div class="account-card-head"><div><div class="account-title">' + t('safe') + ' #' + esc(box.id) + '</div><div class="account-type">' + esc(box.bank_id || '') + ' · ' + esc(box.slots) + ' slots</div></div><span class="badge gold">' + t('rentUntil') + '</span></div><div class="account-balance" style="font-size:14px">' + dateLabel(box.rent_expires_at) + '</div><button class="btn small" data-action="openSafeBox" data-box="' + esc(box.id) + '">' + t('openSafe') + '</button></div>';
    }).join('');
    var tiers = Object.keys(data.safeBoxTiers || {}).sort(function (a, b) { return Number(a) - Number(b); }).map(function (key) {
      var tier = data.safeBoxTiers[key] || {};
      return '<option value="' + esc(key) + '">' + esc(tier.label || (key + ' slots')) + ' · ' + money(tier.price) + '</option>';
    }).join('');
    return pageHead(t('safeIntro'), t('safe'), t('safeIntro')) +
      '<div class="note-box" style="margin-bottom:14px">' + t('safeNote') + '</div>' +
      (safeBoxes.length ? '<div class="account-grid">' + rows + '</div>' : emptyState(t('noSafe'), '▣')) +
      '<section class="panel" style="margin-top:14px"><div class="panel-head"><h3>' + t('rent') + '</h3></div><form data-form="safe-rent" class="form-grid"><div class="field"><label>' + t('sourceAccount') + '</label><select name="accountId">' + accountOptions(function (account) { return account.type === 'checking' && account.canWithdraw; }) + '</select></div><div class="field"><label>' + t('safeTier') + '</label><select name="slots">' + tiers + '</select></div><div class="form-actions field full"><button class="btn" type="submit">' + t('rent') + '</button></div></form></section>';
  }

  function renderCompany() {
    var company = accounts().filter(function (account) { return account.type === 'company'; });
    return pageHead(t('companyIntro'), t('company'), t('companyIntro')) +
      (company.length ? '<div class="account-grid">' + company.map(function (account) { return accountCard(account, false); }).join('') + '</div>' : emptyState(t('noCompany'), '⌂'));
  }

  function renderAdmin() {
    var overview = state.adminData;
    if (!overview) return pageHead(t('adminTitle'), t('admin'), t('adminDesc')) + emptyState(t('noData'));
    var txs = overview.transactions || [];
    var feeValues = (overview.feeVaults || []).map(function (item) { return esc(item.bank_id) + ': ' + money(item.fee_balance); }).join(' · ');
    return pageHead(t('adminTitle'), t('admin'), t('adminDesc'), '<button class="btn secondary" data-action="adminRefresh">↻ ' + t('refresh') + '</button>') +
      '<div class="admin-banner"><div><h2>' + t('adminTitle') + '</h2><p>' + esc(overview.branchCount || 0) + ' ' + t('branchCount') + ' · ' + t('fees') + ': ' + feeValues + '</p></div><div class="admin-mark">⌘</div></div>' +
      '<div class="stats-grid">' + statCard(t('totalLedger'), money(overview.ledgerBalance), '◈', t('accountsCount') + ': ' + esc(overview.accountCount)) + statCard(t('todayVolume'), money(overview.todayVolume), '↔', t('network')) + statCard(t('activeLoans'), String(overview.activeLoans), '↗', t('loanExposure') + ': ' + money(overview.loanBalance)) + statCard(t('ownedATMs'), String(overview.atmCount), '⌂', t('ownerEarnings') + ': ' + money(overview.atmOwnerFees)) + '</div>' +
      '<div class="layout-two"><section class="panel"><div class="panel-head"><h3>' + t('systemTransactions') + '</h3><small>25</small></div><div class="activity-list">' + (txs.length ? txs.map(function (tx) { return transactionRow(tx, { admin: true }); }).join('') : emptyState(t('noTransactions'))) + '</div></section>' +
      '<section class="panel"><div class="panel-head"><h3>' + t('saveSettings') + '</h3><small>' + t('allNetwork') + '</small></div><form data-form="admin-fee" class="form-grid"><div class="field full"><label>' + t('transferFee') + '</label><input name="percent" type="number" min="0" max="' + esc(overview.maxTransferFeePercent == null ? 5 : overview.maxTransferFeePercent) + '" step="0.05" value="' + esc(Number(overview.interBankFeePercent || 0).toFixed(2)) + '" required></div><div class="form-note field full">' + t('fees') + ': ' + feeValues + '</div><div class="form-actions field full"><button class="btn" type="submit">' + t('saveSettings') + '</button></div></form></section></div>';
  }

  function renderUnlock() {
    var selected = state.selectedCard || (state.atmCards[0] && state.atmCards[0].id);
    if (!state.atmCards.length) {
      return '<div class="atm-lock"><div class="atm-lock-head"><div class="atm-logo">⌁</div><h2>' + t('atmTitle') + '</h2><p>' + t('noCards') + '</p></div>' + emptyState(t('noCards'), '▱') + '</div>';
    }
    var cardsHtml = state.atmCards.map(function (card) {
      var active = String(card.id) === String(selected);
      return '<button class="atm-card-option ' + (active ? 'selected' : '') + '" type="button" data-select-card="' + esc(card.id) + '"><span class="atm-card-dot"></span><span><strong>' + esc(card.tier_label || card.tier) + ' · •••• ' + esc(card.last4) + '</strong><small>' + esc(card.account_no || '') + (card.frozen ? ' · ' + t('frozen') : '') + '</small></span></button>';
    }).join('');
    return '<div class="atm-lock"><div class="atm-lock-head"><div class="atm-logo">⌁</div><h2>' + t('atmWelcome') + '</h2><p>' + t('atmDesc') + '</p></div><div class="field"><label>' + t('chooseCard') + '</label></div><div class="atm-card-select">' + cardsHtml + '</div><form data-form="atm-unlock"><input type="hidden" name="cardId" value="' + esc(selected) + '"><div class="field"><label>' + t('pin') + '</label><div class="pin-entry"><input name="pin" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]{4}" autofocus required><button class="btn" type="submit">' + t('unlock') + '</button></div></div></form></div>';
  }

  function render() {
    if (!state.visible) return;
    app.classList.remove('hidden');
    document.getElementById('member-name').textContent = state.data && state.data.user ? state.data.user.name : 'CodeX Admin';
    document.getElementById('member-cid').textContent = state.data && state.data.user ? 'ID ' + state.data.user.citizenid : 'ADMIN CONSOLE';
    document.getElementById('avatar').textContent = state.data && state.data.user ? String(state.data.user.name || 'C').charAt(0).toUpperCase() : 'A';
    document.getElementById('top-network').textContent = t('allNetwork');
    document.getElementById('network-status').textContent = t('network');
    document.getElementById('secure-label').innerHTML = esc(t('secure')) + '<br><b>256-bit ' + 'protection' + '</b>';
    document.getElementById('close-label').textContent = t('close');
    renderNav();
    document.getElementById('page-title').textContent = t(state.page);

    if (state.mode === 'atm' && !state.unlocked) {
      content.innerHTML = renderUnlock();
      var input = content.querySelector('input[name="pin"]');
      if (input) window.setTimeout(function () { input.focus(); }, 50);
      return;
    }

    var view;
    if (state.mode === 'admin') view = renderAdmin();
    else if (state.page === 'overview') view = renderOverview();
    else if (state.page === 'accounts') view = renderAccounts();
    else if (state.page === 'cards') view = renderCards();
    else if (state.page === 'savings') view = renderSavings();
    else if (state.page === 'loans') view = renderLoans();
    else if (state.page === 'invoices') view = renderInvoices();
    else if (state.page === 'cheques') view = renderCheques();
    else if (state.page === 'safe') view = renderSafeBoxes();
    else if (state.page === 'company') view = renderCompany();
    else view = renderOverview();
    content.innerHTML = view;
  }

  function payloadFromForm(form) {
    var formData = new FormData(form);
    var object = {};
    formData.forEach(function (value, key) { object[key] = value; });
    return object;
  }

  function normalizePayload(action, payload) {
    var numeric = ['accountId', 'amount', 'loanId', 'invoiceId', 'chequeId', 'slots', 'cardId'];
    numeric.forEach(function (key) {
      if (Object.prototype.hasOwnProperty.call(payload, key) && payload[key] !== '') payload[key] = Number(payload[key]);
    });
    if (action === 'openSavings' && Object.prototype.hasOwnProperty.call(payload, 'tier') && payload.tier !== '') payload.tier = Number(payload.tier);
    if (action === 'cashCheque' && payload.accountId === '') payload.accountId = null;
    if (Object.prototype.hasOwnProperty.call(payload, 'frozen')) payload.frozen = payload.frozen === '1' || payload.frozen === 1 || payload.frozen === true;
    if (Object.prototype.hasOwnProperty.call(payload, 'percent')) payload.percent = Number(payload.percent);
    return payload;
  }

  function performAction(action, payload) {
    if (state.busy) return Promise.resolve({ ok: false, message: 'busy' });
    state.busy = true;
    app.classList.add('loader');
    payload = normalizePayload(action, payload || {});
    return post('action', { action: action, payload: payload }).then(function (response) {
      state.busy = false;
      app.classList.remove('loader');
      if (response && response.data) {
        state.data = response.data;
        if (state.mode === 'atm' && response.data.session && response.data.session.mode === 'atm') state.unlocked = true;
      }
      if (response && response.ok && action === 'buyATM') {
        state.atmMeta = Object.assign({}, state.atmMeta || {}, { isOwned: true, isOwner: true, surcharge_percent: 0, fee_balance: 0 });
      }
      if (response && response.ok && action === 'setATMSurcharge') {
        state.atmMeta = Object.assign({}, state.atmMeta || {}, { surcharge_percent: Number(payload.percent) || 0 });
      }
      if (response && response.ok && action === 'collectATM') {
        state.atmMeta = Object.assign({}, state.atmMeta || {}, { fee_balance: 0 });
      }
      if (response && response.ok) toast(response.message || 'welcome', 'success');
      else toast(errorText(response && response.message), 'error');
      render();
      return response;
    }).catch(function () {
      state.busy = false;
      app.classList.remove('loader');
      toast(errorText('server_error'), 'error');
      render();
      return { ok: false };
    });
  }

  function performAdminAction(action, payload) {
    if (state.busy) return;
    state.busy = true;
    app.classList.add('loader');
    post('action', { action: action, payload: payload || {} }).then(function (response) {
      state.busy = false;
      app.classList.remove('loader');
      if (response && response.overview) state.adminData = response.overview;
      if (response && response.ok) toast(response.message || 'settingSaved', 'success');
      else toast(errorText(response && response.message), 'error');
      render();
    }).catch(function () {
      state.busy = false;
      app.classList.remove('loader');
      toast(errorText('server_error'), 'error');
    });
  }

  function formAction(form, payload) {
    var kind = form.getAttribute('data-form');
    if (kind === 'admin-fee') {
      performAdminAction('setInterBankFee', { percent: Number(payload.percent) });
      return;
    }
    var map = {
      'atm-unlock': 'unlockCard',
      deposit: 'deposit',
      withdraw: 'withdraw',
      transfer: 'transfer',
      'open-savings': 'openSavings',
      'open-shared': 'createSharedAccount',
      'add-member': 'addMember',
      'savings-goal': 'setSavingsGoal',
      'create-card': 'createCard',
      'loan-apply': 'applyLoan',
      'loan-pay': 'payLoan',
      'invoice-create': 'createInvoice',
      'invoice-pay': 'payInvoice',
      'cheque-create': 'issueCheque',
      'cheque-cash': 'cashCheque',
      'safe-rent': 'rentSafeBox',
      'atm-surcharge': 'setATMSurcharge'
    };
    var action = map[kind];
    if (action) performAction(action, payload);
  }

  document.addEventListener('click', function (event) {
    var pageButton = event.target.closest('[data-page]');
    if (pageButton) {
      var page = pageButton.getAttribute('data-page');
      if (state.mode === 'admin' && page !== 'admin') return;
      if (state.mode === 'atm' && ['overview', 'cards'].indexOf(page) === -1) return;
      state.page = page;
      render();
      return;
    }
    var cardSelect = event.target.closest('[data-select-card]');
    if (cardSelect) {
      state.selectedCard = cardSelect.getAttribute('data-select-card');
      render();
      return;
    }
    var actionButton = event.target.closest('[data-action]');
    if (actionButton) {
      var action = actionButton.getAttribute('data-action');
      if (action === 'adminRefresh') {
        post('adminRefresh', {}).then(function (response) { if (response && response.overview) { state.adminData = response.overview; render(); } });
      } else if (action === 'freezeCard') {
        performAction('freezeCard', { cardId: Number(actionButton.getAttribute('data-card')), frozen: actionButton.getAttribute('data-frozen') === '1' });
      } else if (action === 'cancelCheque') {
        performAction('cancelCheque', { chequeId: Number(actionButton.getAttribute('data-cheque')) });
      } else if (action === 'removeMember') {
        performAction('removeMember', { accountId: Number(actionButton.getAttribute('data-account')), citizenid: actionButton.getAttribute('data-citizen') });
      } else if (action === 'upgradeAccount') {
        performAction('upgradeAccount', { accountId: Number(actionButton.getAttribute('data-account')) });
      } else if (action === 'openSafeBox') {
        performAction('openSafeBox', { boxId: Number(actionButton.getAttribute('data-box')) });
      } else if (action === 'buyATM') {
        performAction('buyATM', { accountId: Number(actionButton.getAttribute('data-account')) });
      } else if (action === 'collectATM') {
        performAction('collectATM', { accountId: Number(actionButton.getAttribute('data-account')) });
      }
    }
  });

  document.addEventListener('submit', function (event) {
    var form = event.target.closest('form[data-form]');
    if (!form) return;
    event.preventDefault();
    formAction(form, payloadFromForm(form));
  });

  document.getElementById('close-button').addEventListener('click', close);
  document.getElementById('close-icon').addEventListener('click', close);
  window.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && state.visible) {
      event.preventDefault();
      close();
    }
  });

  window.addEventListener('message', function (event) {
    var message = event.data || {};
    if (message.type === 'open') {
      state.visible = true;
      state.mode = message.mode || 'bank';
      state.locale = 'en';
      state.currencySymbol = message.currencySymbol || '$';
      state.token = message.token;
      state.unlocked = state.mode !== 'atm';
      state.page = state.mode === 'admin' ? 'admin' : 'overview';
      state.data = message.data || null;
      state.atmMeta = null;
      state.adminData = null;
      render();
      return;
    }
    if (message.type === 'openAtm') {
      state.visible = true;
      state.mode = 'atm';
      state.locale = 'en';
      state.currencySymbol = message.currencySymbol || '$';
      state.token = message.token;
      state.unlocked = false;
      state.page = 'overview';
      state.data = null;
      state.atmCards = message.cards || [];
      state.atmMeta = message.atm || null;
      state.selectedCard = state.atmCards[0] ? state.atmCards[0].id : null;
      render();
      return;
    }
    if (message.type === 'update') {
      state.data = message.data || state.data;
      if (state.mode === 'atm' && state.data && state.data.session && state.data.session.mode === 'atm') state.unlocked = true;
      render();
      return;
    }
    if (message.type === 'adminData') {
      state.adminData = message.overview || null;
      render();
      return;
    }
    if (message.type === 'toast') {
      toast(message.message, message.kind);
      return;
    }
    if (message.type === 'close') {
      state.visible = false;
      state.data = null;
      state.token = null;
      state.unlocked = false;
      app.classList.add('hidden');
      return;
    }
  });
})();
