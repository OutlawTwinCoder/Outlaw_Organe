const appEl = document.getElementById('app');
const subtitleEl = document.getElementById('panel-subtitle');
const summaryEl = document.getElementById('summary');
const overviewEl = document.getElementById('overview-content');
const deliveriesEl = document.getElementById('deliveries-content');
const rareEl = document.getElementById('rare-content');
const upgradesEl = document.getElementById('upgrades-content');
const shopEl = document.getElementById('shop-content');
const closeBtn = document.getElementById('close-btn');
const tabButtons = Array.from(document.querySelectorAll('.tab'));
const tabPanels = Array.from(document.querySelectorAll('.tab-panel'));

const isNui = typeof GetParentResourceName === 'function';
const resourceName = isNui ? GetParentResourceName() : 'outlaw_organ';
const numberFormat = new Intl.NumberFormat('fr-FR');

const state = {
    visible: false,
    tab: 'overview',
    data: null
};

function formatNumber(value) {
    const num = Number.isFinite(value) ? value : 0;
    return numberFormat.format(Math.round(num));
}

function formatCurrency(value) {
    const num = Number.isFinite(value) ? value : 0;
    return '$' + numberFormat.format(Math.round(num));
}

function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
}

function showApp() {
    if (state.visible) return;
    appEl.classList.remove('hidden');
    state.visible = true;
}

function hideApp() {
    if (!state.visible) return;
    appEl.classList.add('hidden');
    state.visible = false;
}

function send(eventName, payload) {
    if (isNui) {
        fetch(`https://${resourceName}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload || {})
        });
    } else {
        console.log('[NUI]', eventName, payload);
    }
}

function setTab(tab) {
    if (state.tab === tab) return;
    state.tab = tab;
    updateTabs();
    renderActiveTab();
}

function updateTabs() {
    tabButtons.forEach((btn) => {
        const isActive = btn.dataset.tab === state.tab;
        btn.classList.toggle('active', isActive);
    });
    tabPanels.forEach((panel) => {
        const isActive = panel.dataset.tab === state.tab;
        panel.classList.toggle('active', isActive);
    });
}

function updateSubtitle() {
    if (!state.data) {
        subtitleEl.textContent = '';
        return;
    }
    const parts = [];
    if (state.data.tier && state.data.tier.name) {
        parts.push(`Rang ${state.data.tier.name}`);
    }
    parts.push(`${formatNumber(state.data.reputation || 0)} RP`);
    if (Number.isFinite(state.data.multiplier)) {
        parts.push(`Bonus x${(state.data.multiplier || 1).toFixed(2)}`);
    }
    subtitleEl.textContent = parts.join(' • ');
}

function renderSummary() {
    if (!state.data) {
        summaryEl.innerHTML = '';
        return;
    }

    const reputation = Number(state.data.reputation || 0);
    const tier = state.data.tier || {};
    const nextTier = state.data.nextTier || null;
    const tierStart = Number(tier.reputation || 0);
    const tierEnd = nextTier ? Number(nextTier.reputation || 0) : reputation;
    const progress = nextTier ? clamp((reputation - tierStart) / Math.max(tierEnd - tierStart, 1), 0, 1) : 1;
    const progressLabel = nextTier ? `Prochain rang: ${nextTier.name} (${formatNumber(tierEnd)} RP)` : 'Rang maximal atteint';
    const multiplier = Number(state.data.multiplier || 1);
    const scalpel = state.data.scalpel || null;
    const secondChance = scalpel ? Math.round((scalpel.secondChance || 0) * 100) : 0;

    summaryEl.innerHTML = `
        <article class="summary-card rep">
            <div class="summary-title">Réputation</div>
            <div class="summary-value">${formatNumber(reputation)}<span>RP</span></div>
            <div class="summary-meta">${tier.name ? `Rang actuel: ${tier.name}` : 'Rang inconnu'}</div>
            <div class="progress-bar"><span style="width:${Math.round(progress * 100)}%"></span></div>
            <div class="summary-meta">${progressLabel}</div>
        </article>
        <article class="summary-card">
            <div class="summary-title">Bonus prix</div>
            <div class="summary-value">${multiplier.toFixed(2)}<span>x</span></div>
            <div class="summary-meta">Appliqué sur les ventes au trafiquant.</div>
        </article>
        <article class="summary-card summary-card--scalpel">
            <div class="summary-title">Scalpel actif</div>
            <div class="summary-value">${scalpel ? scalpel.label : 'Aucun'}${scalpel ? `<span>+${formatNumber(scalpel.bonusQuality || 0)} qualité</span>` : ''}</div>
            <div class="summary-meta">${scalpel ? `Chance double prélèvement: ${secondChance}%` : 'Achetez un scalpel pour améliorer vos récoltes.'}</div>
            <div class="summary-actions">
                <button class="primary-button" id="summary-sell" type="button">Vendre mon stock</button>
                <button class="secondary-button" data-go-tab="deliveries" type="button">Livraisons</button>
                <button class="secondary-button" data-go-tab="shop" type="button">Boutique</button>
            </div>
        </article>
    `;

    const sellBtn = summaryEl.querySelector('#summary-sell');
    if (sellBtn) {
        sellBtn.addEventListener('click', () => send('dealer_sell'));
    }
    summaryEl.querySelectorAll('[data-go-tab]').forEach((btn) => {
        btn.addEventListener('click', (event) => {
            const tab = event.currentTarget.getAttribute('data-go-tab');
            state.tab = tab;
            updateTabs();
            renderActiveTab();
        });
    });
}

function renderOverview() {
    const data = state.data || {};
    const stats = data.stats || {};
    const deliveries = Array.isArray(data.deliveries) ? data.deliveries : [];
    const rare = Array.isArray(data.rare) ? data.rare : [];
    const unlockedRare = rare.filter((entry) => entry.unlocked).length;
    const nextRare = rare.find((entry) => !entry.unlocked);
    const totalDeliveries = deliveries.reduce((sum, entry) => sum + (entry.count || 0), 0);

    overviewEl.innerHTML = '';

    const statsCard = document.createElement('article');
    statsCard.className = 'card';
    statsCard.innerHTML = `
        <h2>Contrats & ventes</h2>
        <div class="stat-list">
            <div class="stat-row"><span>Contrats terminés</span><strong>${formatNumber(stats.contracts || 0)}</strong></div>
            <div class="stat-row"><span>Qualité moyenne</span><strong>${formatNumber(stats.averageQuality || 0)}%</strong></div>
            <div class="stat-row"><span>Meilleure qualité</span><strong>${formatNumber(stats.bestQuality || 0)}%</strong></div>
            <div class="stat-row"><span>Organes vendus</span><strong>${formatNumber(stats.totalSales || 0)}</strong></div>
        </div>
    `;
    overviewEl.appendChild(statsCard);

    const rareCard = document.createElement('article');
    rareCard.className = 'card';
    rareCard.innerHTML = `
        <h2>Commandes spéciales</h2>
        <div class="stat-list">
            <div class="stat-row"><span>Débloquées</span><strong>${unlockedRare}/${rare.length}</strong></div>
            <div class="stat-row"><span>Livraisons totales</span><strong>${formatNumber(totalDeliveries)}</strong></div>
            <div class="stat-row"><span>Prochaine pièce</span><strong>${nextRare ? `${nextRare.label} (${formatNumber(nextRare.required || 0)} RP)` : 'Toutes débloquées'}</strong></div>
        </div>
        <button class="secondary-button" data-go-tab="rare" type="button">Voir les commandes</button>
    `;
    overviewEl.appendChild(rareCard);

    overviewEl.querySelectorAll('[data-go-tab]').forEach((btn) => {
        btn.addEventListener('click', (event) => {
            const tab = event.currentTarget.getAttribute('data-go-tab');
            state.tab = tab;
            updateTabs();
            renderActiveTab();
        });
    });
}

function renderDeliveries() {
    const data = state.data || {};
    const deliveries = Array.isArray(data.deliveries) ? data.deliveries : [];
    const reputation = Number(data.reputation || 0);
    const multiplier = Number(data.multiplier || 1);
    deliveriesEl.innerHTML = '';

    if (!deliveries.length) {
        deliveriesEl.innerHTML = '<div class="empty-placeholder">Aucune livraison enregistrée pour le moment.</div>';
        return;
    }

    deliveries.forEach((delivery) => {
        const unlock = Number(delivery.unlock || 0);
        const unlocked = reputation >= unlock;
        const card = document.createElement('article');
        card.className = `list-card${unlocked ? '' : ' locked'}`;
        const basePrice = Number(delivery.price || 0);
        const adjustedPrice = basePrice * multiplier;
        const adjustedLine = multiplier !== 1
            ? `<div class="list-meta accent">Prix ${multiplier > 1 ? 'bonus' : 'réduit'} (${multiplier.toFixed(2)}x): ${formatCurrency(adjustedPrice)}</div>`
            : '';
        card.innerHTML = `
            <h3 class="list-title">${delivery.label || delivery.name}</h3>
            <div class="list-meta">Livraisons totales: <strong>${formatNumber(delivery.count || 0)}</strong></div>
            <div class="list-meta">Prix de base: ${formatCurrency(basePrice)}</div>
            ${adjustedLine}
            <div class="list-footer">
                <span class="tag${unlocked ? ' accent' : ''}">${unlock > 0 ? `${formatNumber(unlock)} RP requis` : 'Disponible'}</span>
            </div>
        `;
        deliveriesEl.appendChild(card);
    });
}

function renderRare() {
    const data = state.data || {};
    const rare = Array.isArray(data.rare) ? data.rare : [];
    rareEl.innerHTML = '';

    if (!rare.length) {
        rareEl.innerHTML = '<div class="empty-placeholder">Aucune commande rare disponible.</div>';
        return;
    }

    rare.forEach((entry) => {
        const unlocked = Boolean(entry.unlocked);
        const card = document.createElement('article');
        card.className = `list-card${unlocked ? '' : ' locked'}`;
        card.innerHTML = `
            <h3 class="list-title">${entry.label || entry.name}</h3>
            <div class="list-meta">Réputation requise: ${formatNumber(entry.required || 0)} RP</div>
            <div class="list-footer">
                <span class="tag${unlocked ? ' accent' : ''}">${unlocked ? 'Débloqué' : 'Verrouillé'}</span>
            </div>
        `;
        rareEl.appendChild(card);
    });
}

function renderUpgrades() {
    const data = state.data || {};
    const upgrades = Array.isArray(data.upgrades) ? data.upgrades : [];
    upgradesEl.innerHTML = '';

    if (!upgrades.length) {
        upgradesEl.innerHTML = '<div class="empty-placeholder">Aucune amélioration disponible pour le moment.</div>';
        return;
    }

    upgrades.forEach((upgrade) => {
        const card = document.createElement('article');
        card.className = 'list-card';
        const status = upgrade.status || 'locked';
        const price = Number(upgrade.price || 0);
        const requirements = Array.isArray(upgrade.reasons) ? upgrade.reasons : [];
        const requirementsHtml = requirements.length
            ? requirements.map((reason) => `<span>${reason}</span>`).join('')
            : '<span>Toutes les conditions sont réunies.</span>';

        card.innerHTML = `
            <h3 class="list-title">${upgrade.label}</h3>
            <div class="list-meta">Prix: ${formatCurrency(price)}</div>
            <div class="list-meta">Réputation requise: ${formatNumber(upgrade.reputation || 0)} RP</div>
            <div class="requirements">${requirementsHtml}</div>
            <div class="list-footer">
                <span class="tag${status === 'ready' ? ' accent' : ''}">${status === 'ready' ? 'Disponible' : status === 'owned' ? 'Obtenu' : 'Verrouillé'}</span>
                <button class="${status === 'ready' ? 'primary-button' : 'secondary-button'}" type="button" data-upgrade="${upgrade.id}" ${status === 'ready' ? '' : 'disabled'}>${status === 'ready' ? `Débloquer (${formatCurrency(price)})` : 'Indisponible'}</button>
            </div>
        `;

        const button = card.querySelector('[data-upgrade]');
        if (button && status === 'ready') {
            button.addEventListener('click', () => {
                send('dealer_upgrade', { id: upgrade.id });
            });
        }
        upgradesEl.appendChild(card);
    });
}

function renderShop() {
    const data = state.data || {};
    const shop = data.shop || {};
    const variants = Array.isArray(shop.variants) ? shop.variants : [];
    const kit = shop.kit || null;
    shopEl.innerHTML = '';

    if (!variants.length && !kit) {
        shopEl.innerHTML = '<div class="empty-placeholder">Aucun outil disponible à l’achat.</div>';
        return;
    }

    const items = [...variants];
    if (kit) {
        items.push({ ...kit, isKit: true });
    }

    items.forEach((item) => {
        const card = document.createElement('article');
        card.className = 'list-card';
        let description = '';
        if (!item.isKit) {
            const chance = Math.round((item.secondChance || 0) * 100);
            description = `Bonus qualité: +${formatNumber(item.bonusQuality || 0)} | Chance double: ${chance}%`;
        } else {
            description = 'Ajoute du temps de conservation supplémentaire pour les organes.';
        }

        const isLocked = Boolean(item.locked);
        const isOwned = Boolean(item.owned);
        const buttonText = item.isKit ? `Acheter (${formatCurrency(item.price || 0)})` : `Acheter (${formatCurrency(item.price || 0)})`;

        card.innerHTML = `
            <h3 class="list-title">${item.label}</h3>
            <div class="list-meta">${item.isKit ? '' : `Réputation requise: ${formatNumber(item.reputation || 0)} RP`}</div>
            <div class="list-description">${description}</div>
            <div class="list-footer">
                <span class="tag${!isLocked && !item.isKit ? ' accent' : ''}">${item.isKit ? 'Consommable' : isLocked ? 'Réputation requise' : (isOwned ? 'Possédé' : 'Disponible')}</span>
                <button class="${!isLocked && !isOwned ? 'primary-button' : 'secondary-button'}" type="button" data-shop-id="${item.id}" ${(!isLocked && !isOwned) ? '' : 'disabled'}>${isOwned ? 'Possédé' : isLocked ? 'Verrouillé' : buttonText}</button>
            </div>
        `;

        const button = card.querySelector('[data-shop-id]');
        if (button && !isLocked && !isOwned) {
            button.addEventListener('click', () => {
                send('dealer_buy', { id: item.id });
            });
        }

        shopEl.appendChild(card);
    });
}

function renderActiveTab() {
    switch (state.tab) {
        case 'overview':
            renderOverview();
            break;
        case 'deliveries':
            renderDeliveries();
            break;
        case 'rare':
            renderRare();
            break;
        case 'upgrades':
            renderUpgrades();
            break;
        case 'shop':
            renderShop();
            break;
        default:
            renderOverview();
            break;
    }
}

function renderAll() {
    updateSubtitle();
    renderSummary();
    updateTabs();
    renderActiveTab();
}

closeBtn.addEventListener('click', () => {
    hideApp();
    send('dealer_close');
});

document.addEventListener('keydown', (event) => {
    if (!state.visible) return;
    if (event.key === 'Escape') {
        event.preventDefault();
        hideApp();
        send('dealer_close');
    }
});

tabButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;
        state.tab = tab;
        updateTabs();
        renderActiveTab();
    });
});

window.addEventListener('message', (event) => {
    const { action, payload } = event.data || {};
    if (action === 'openDealer') {
        state.data = payload || {};
        state.tab = 'overview';
        renderAll();
        showApp();
    } else if (action === 'closeDealer') {
        hideApp();
    } else if (action === 'updateDealer') {
        state.data = payload || state.data;
        if (state.visible) {
            renderAll();
        }
    }
});

if (!isNui) {
    window.addEventListener('DOMContentLoaded', () => {
        const sampleData = {
            reputation: 350,
            multiplier: 1.25,
            tier: { name: 'Dissecteur', reputation: 320 },
            nextTier: { name: 'Chirurgien', reputation: 620 },
            scalpel: { label: 'Scalpel (pro)', bonusQuality: 10, secondChance: 0.2 },
            stats: { contracts: 12, averageQuality: 82, bestQuality: 96, totalSales: 54 },
            deliveries: [
                { name: 'rein', label: 'Rein', count: 32, price: 400, unlock: 0 },
                { name: 'coeur', label: 'Cœur', count: 6, price: 900, unlock: 320 },
                { name: 'yeux', label: 'Yeux', count: 14, price: 250, unlock: 120 }
            ],
            rare: [
                { name: 'coeur', label: 'Commande cœur', required: 320, unlocked: true },
                { name: 'cerveau', label: 'Commande cranienne', required: 580, unlocked: false }
            ],
            upgrades: [
                { id: 'elite', label: 'Scalpel (élite)', price: 5500, reputation: 380, status: 'ready', reasons: [] },
                { id: 'mythic', label: 'Scalpel (mythique)', price: 7800, reputation: 800, status: 'locked', reasons: ['Réputation 350/800', 'Cœur 6/12'] }
            ],
            shop: {
                variants: [
                    { id: 'basic', label: 'Scalpel (basique)', price: 250, reputation: 0, bonusQuality: 0, secondChance: 0, locked: false, owned: false },
                    { id: 'pro', label: 'Scalpel (pro)', price: 1500, reputation: 120, bonusQuality: 10, secondChance: 0.2, locked: false, owned: true },
                    { id: 'elite', label: 'Scalpel (élite)', price: 2800, reputation: 380, bonusQuality: 18, secondChance: 0.35, locked: true, owned: false }
                ],
                kit: { id: 'kit', label: 'Kit chirurgical', price: 400 }
            }
        };
        state.data = sampleData;
        state.tab = 'overview';
        renderAll();
        showApp();
    });
}
