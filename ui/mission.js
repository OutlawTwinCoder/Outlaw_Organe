const missionAppEl = document.getElementById('mission-app');
if (missionAppEl) {
    const missionSubtitleEl = document.getElementById('mission-subtitle');
    const missionSummaryEl = document.getElementById('mission-summary');
    const missionProgressEl = document.getElementById('mission-progress-content');
    const missionContractsEl = document.getElementById('mission-contracts-content');
    const missionPoolEl = document.getElementById('mission-pool-content');
    const missionCloseBtn = document.getElementById('mission-close-btn');
    const missionTabButtons = Array.from(missionAppEl.querySelectorAll('[data-mission-tab]'));
    const missionTabPanels = Array.from(missionAppEl.querySelectorAll('.tab-panel'));

    const missionNumberFormat = new Intl.NumberFormat('fr-FR');

    const missionState = {
        visible: false,
        tab: 'progress',
        data: null
    };

    function formatNumber(value) {
        const num = Number.isFinite(value) ? value : 0;
        return missionNumberFormat.format(Math.round(num));
    }

    function formatCurrency(value) {
        const num = Number.isFinite(value) ? value : 0;
        return '$' + missionNumberFormat.format(Math.round(num));
    }

    function formatDuration(seconds) {
        const total = Math.max(0, Math.floor(seconds || 0));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const secs = total % 60;
        if (hours > 0) {
            return `${hours}h${String(minutes).padStart(2, '0')}m`;
        }
        return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    function showMissionApp() {
        if (missionState.visible) return;
        missionAppEl.classList.remove('hidden');
        missionState.visible = true;
    }

    function hideMissionApp() {
        if (!missionState.visible) return;
        missionAppEl.classList.add('hidden');
        missionState.visible = false;
    }

    function updateMissionTabs() {
        missionTabButtons.forEach((btn) => {
            const isActive = btn.dataset.missionTab === missionState.tab;
            btn.classList.toggle('active', isActive);
        });
        missionTabPanels.forEach((panel) => {
            const isActive = panel.dataset.missionTab === missionState.tab;
            panel.classList.toggle('active', isActive);
        });
    }

    function updateMissionSubtitle() {
        const data = missionState.data;
        if (!data) {
            missionSubtitleEl.textContent = '';
            return;
        }
        const parts = [];
        const rep = Number(data.reputation || 0);
        parts.push(`${formatNumber(rep)} RP`);
        if (Number.isFinite(data.unlockedCount) && Number.isFinite(data.totalContracts)) {
            parts.push(`${formatNumber(data.unlockedCount || 0)}/${formatNumber(data.totalContracts || 0)} débloqués`);
        }
        const cooldown = Math.max(0, Number(data.cooldown || 0));
        if (cooldown > 0) {
            parts.push(`Cooldown ${formatDuration(cooldown)}`);
        }
        missionSubtitleEl.textContent = parts.join(' • ');
    }

    function renderMissionSummary() {
        const data = missionState.data;
        if (!data) {
            missionSummaryEl.innerHTML = '';
            return;
        }

        const rep = Number(data.reputation || 0);
        const unlockedCount = Number(data.unlockedCount || 0);
        const totalContracts = Number(data.totalContracts || 0);
        const stats = data.stats || {};
        const active = data.active || null;
        const cooldown = Math.max(0, Number(data.cooldown || 0));
        const canStartRandom = Boolean(data.canStartRandom);
        const nextUnlock = data.nextUnlock || null;

        const nextLine = nextUnlock
            ? `Prochain contrat: ${nextUnlock.label} (${Math.round((nextUnlock.progress || 0) * 100)}%)`
            : 'Tous les contrats sont débloqués.';

        const deliveriesLine = `Livraisons totales: ${formatNumber(stats.totalDelivered || 0)}`;
        const contractsLine = `Contrats terminés: ${formatNumber(stats.contracts || 0)}`;

        let activeLine = 'Aucune mission en cours.';
        if (active) {
            const label = active.itemLabel ? `${active.label} • ${active.itemLabel}` : active.label;
            if (active.remaining && active.remaining > 0) {
                activeLine = `${label} — ${formatDuration(active.remaining)} restantes`;
            } else {
                activeLine = `${label}`;
            }
        } else if (cooldown > 0) {
            activeLine = `Disponible après ${formatDuration(cooldown)}`;
        }

        let quickLabel = 'Mission express';
        let quickDisabled = false;
        if (active) {
            quickLabel = 'Mission active';
            quickDisabled = true;
        } else if (cooldown > 0) {
            quickLabel = `Cooldown (${formatDuration(cooldown)})`;
            quickDisabled = true;
        } else if (!canStartRandom) {
            quickDisabled = true;
        }

        missionSummaryEl.innerHTML = `
            <article class="summary-card rep">
                <div class="summary-title">Réputation</div>
                <div class="summary-value">${formatNumber(rep)}<span>RP</span></div>
                <div class="summary-meta">Contrats débloqués: ${formatNumber(unlockedCount)}/${formatNumber(totalContracts)}</div>
                <div class="summary-meta">${nextLine}</div>
            </article>
            <article class="summary-card">
                <div class="summary-title">Statut</div>
                <div class="summary-meta">${contractsLine}</div>
                <div class="summary-meta">${deliveriesLine}</div>
                <div class="summary-meta">${activeLine}</div>
            </article>
            <article class="summary-card summary-card--actions">
                <div class="summary-title">Actions rapides</div>
                <div class="summary-meta">Gère tes contrats depuis la planque.</div>
                <div class="summary-actions">
                    <button class="primary-button" id="mission-quickstart" type="button" ${quickDisabled ? 'disabled' : ''}>${quickLabel}</button>
                    <button class="secondary-button" data-go-mission-tab="contracts" type="button">Voir les contrats</button>
                </div>
            </article>
        `;

        const quickBtn = missionSummaryEl.querySelector('#mission-quickstart');
        if (quickBtn && !quickDisabled) {
            quickBtn.addEventListener('click', () => {
                if (typeof send === 'function') {
                    send('mission_start', {});
                }
            });
        }
        missionSummaryEl.querySelectorAll('[data-go-mission-tab]').forEach((btn) => {
            btn.addEventListener('click', (event) => {
                const tab = event.currentTarget.getAttribute('data-go-mission-tab');
                missionState.tab = tab;
                updateMissionTabs();
                renderMissionActiveTab();
            });
        });
    }

    function renderMissionProgress() {
        const data = missionState.data || {};
        const contracts = Array.isArray(data.contracts) ? data.contracts : [];
        missionProgressEl.innerHTML = '';

        if (!contracts.length) {
            missionProgressEl.innerHTML = '<div class="empty-placeholder">Aucun contrat configuré.</div>';
            return;
        }

        contracts.forEach((contract) => {
            const card = document.createElement('article');
            card.className = 'list-card';
            if (!contract.unlocked) {
                card.classList.add('locked');
            }
            const percent = Math.round((contract.progress || 0) * 100);
            const reqs = Array.isArray(contract.requirements) ? contract.requirements : [];
            const requirementsHtml = reqs.length
                ? reqs.map((req) => {
                    const required = Number(req.required || 0);
                    const have = Number(req.value || 0);
                    const ratio = required > 0 ? Math.min(1, have / required) : 1;
                    const label = req.label || (req.type === 'reputation' ? 'Réputation' : req.name || 'Objectif');
                    return `
                        <div class="requirement-row">
                            <div class="requirement-row-header">
                                <span>${label}</span>
                                <strong>${formatNumber(have)}/${formatNumber(required)}</strong>
                            </div>
                            <div class="progress-bar progress-bar--thin"><span style="width:${Math.round(ratio * 100)}%"></span></div>
                        </div>
                    `;
                }).join('')
                : '<span>Aucune exigence.</span>';

            const historyLine = contract.completed > 0
                ? `Terminé ${formatNumber(contract.completed)} fois${contract.bestTime ? ` • Record ${formatDuration(contract.bestTime)}` : ''}`
                : 'Pas encore terminé.';

            card.innerHTML = `
                <div class="list-header">
                    <h3 class="list-title">${contract.label}</h3>
                    <span class="tag${contract.unlocked ? ' accent' : ''}">${contract.unlocked ? 'Débloqué' : 'Verrouillé'}</span>
                </div>
                <div class="list-meta">Progression globale: ${percent}%</div>
                <div class="requirements requirements--progress">${requirementsHtml}</div>
                <div class="list-meta">${historyLine}</div>
            `;

            missionProgressEl.appendChild(card);
        });
    }

    function renderMissionContracts() {
        const data = missionState.data || {};
        const contracts = Array.isArray(data.contracts) ? data.contracts : [];
        missionContractsEl.innerHTML = '';

        if (!contracts.length) {
            missionContractsEl.innerHTML = '<div class="empty-placeholder">Aucun contrat disponible pour le moment.</div>';
            return;
        }

        const hasActive = Boolean(data.active);
        const cooldown = Math.max(0, Number(data.cooldown || 0));

        contracts.forEach((contract) => {
            const card = document.createElement('article');
            card.className = 'list-card';
            if (!contract.unlocked) {
                card.classList.add('locked');
            }

            const fee = Number(contract.fee || 0);
            const priceLabel = fee > 0 ? formatCurrency(fee) : 'Gratuit';
            const timeLabel = contract.timeLimit > 0 ? formatDuration(contract.timeLimit) : '—';
            const bonusLine = contract.bonusReputation > 0
                ? `<div class="list-meta">Bonus réputation: +${formatNumber(contract.bonusReputation)}</div>`
                : '';
            const timeLine = contract.timeLimit > 0
                ? `<div class="list-meta">Temps limite: ${timeLabel}</div>`
                : '';
            const historyLine = contract.completed > 0
                ? `<div class="list-meta">Succès: ${formatNumber(contract.completed)}${contract.bestTime ? ` • Record ${formatDuration(contract.bestTime)}` : ''}</div>`
                : '';
            const description = contract.description || 'Aucune description.';

            let tagText;
            let tagAccent = false;
            let buttonLabel;
            let buttonDisabled = false;

            if (data.active && data.active.id === contract.id) {
                tagText = 'En cours';
                tagAccent = true;
                buttonLabel = 'Mission en cours';
                buttonDisabled = true;
            } else if (!contract.unlocked) {
                tagText = 'Verrouillé';
                buttonLabel = 'Verrouillé';
                buttonDisabled = true;
            } else if (hasActive) {
                tagText = 'Mission active';
                buttonLabel = 'Mission active';
                buttonDisabled = true;
            } else if (cooldown > 0) {
                tagText = 'Cooldown';
                buttonLabel = `Attends ${formatDuration(cooldown)}`;
                buttonDisabled = true;
            } else {
                tagText = 'Disponible';
                tagAccent = true;
                buttonLabel = fee > 0 ? `Acheter (${priceLabel})` : 'Démarrer';
            }

            const reasons = Array.isArray(contract.reasons) ? contract.reasons : [];
            const reasonHtml = !contract.unlocked && reasons.length
                ? `<div class="requirements">${reasons.map((reason) => `<span>${reason}</span>`).join('')}</div>`
                : '';

            card.innerHTML = `
                <div class="list-header">
                    <h3 class="list-title">${contract.label}</h3>
                    <span class="list-price">${priceLabel}</span>
                </div>
                <div class="list-description">${description}</div>
                ${timeLine}
                ${bonusLine}
                ${historyLine}
                ${reasonHtml}
                <div class="list-footer">
                    <span class="tag${tagAccent ? ' accent' : ''}">${tagText}</span>
                    <button class="${(!buttonDisabled) ? 'primary-button' : 'secondary-button'}" type="button" data-contract-id="${contract.id}" ${buttonDisabled ? 'disabled' : ''}>${buttonLabel}</button>
                </div>
            `;

            const button = card.querySelector('[data-contract-id]');
            if (button && !buttonDisabled) {
                button.addEventListener('click', () => {
                    if (typeof send === 'function') {
                        send('mission_start', { contract: contract.id });
                    }
                });
            }

            missionContractsEl.appendChild(card);
        });
    }

    function renderMissionPool() {
        const data = missionState.data || {};
        const pool = data.pool || {};
        const unlocked = Array.isArray(pool.unlocked) ? pool.unlocked : [];
        const locked = Array.isArray(pool.locked) ? pool.locked : [];
        missionPoolEl.innerHTML = '';

        const contractMap = new Map();
        if (Array.isArray(data.contracts)) {
            data.contracts.forEach((contract) => {
                contractMap.set(contract.id, contract);
            });
        }

        if (!unlocked.length && !locked.length) {
            missionPoolEl.innerHTML = '<div class="empty-placeholder">Aucun organe configuré.</div>';
            return;
        }

        const renderItem = (item, available) => {
            const card = document.createElement('article');
            card.className = `list-card list-card--compact${available ? '' : ' locked'}`;
            const contract = contractMap.get(item.id);
            let reasonBlock = '';
            if (!available && contract && Array.isArray(contract.reasons) && contract.reasons.length) {
                reasonBlock = `<div class="requirements">${contract.reasons.map((reason) => `<span>${reason}</span>`).join('')}</div>`;
            }
            card.innerHTML = `
                <h3 class="list-title">${item.label}</h3>
                <div class="list-meta">${available ? 'Disponible dans les missions aléatoires.' : 'Encore verrouillé.'}</div>
                ${reasonBlock}
                <div class="list-footer">
                    <span class="tag${available ? ' accent' : ''}">${available ? 'Disponible' : 'Verrouillé'}</span>
                </div>
            `;
            missionPoolEl.appendChild(card);
        };

        unlocked.forEach((item) => renderItem(item, true));
        locked.forEach((item) => renderItem(item, false));
    }

    function renderMissionActiveTab() {
        switch (missionState.tab) {
            case 'progress':
                renderMissionProgress();
                break;
            case 'contracts':
                renderMissionContracts();
                break;
            case 'pool':
                renderMissionPool();
                break;
            default:
                renderMissionProgress();
                break;
        }
    }

    function renderMissionAll() {
        updateMissionSubtitle();
        renderMissionSummary();
        updateMissionTabs();
        renderMissionActiveTab();
    }

    missionCloseBtn.addEventListener('click', () => {
        hideMissionApp();
        if (typeof send === 'function') {
            send('mission_close');
        }
    });

    document.addEventListener('keydown', (event) => {
        if (!missionState.visible) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            hideMissionApp();
            if (typeof send === 'function') {
                send('mission_close');
            }
        }
    });

    missionTabButtons.forEach((btn) => {
        btn.addEventListener('click', () => {
            const tab = btn.dataset.missionTab;
            missionState.tab = tab;
            updateMissionTabs();
            renderMissionActiveTab();
        });
    });

    window.addEventListener('message', (event) => {
        const { action, payload } = event.data || {};
        if (action === 'openMission') {
            missionState.data = payload || {};
            missionState.tab = 'progress';
            renderMissionAll();
            showMissionApp();
        } else if (action === 'closeMission') {
            hideMissionApp();
        } else if (action === 'updateMission') {
            missionState.data = payload || missionState.data;
            if (missionState.visible) {
                renderMissionAll();
            }
        }
    });
}
