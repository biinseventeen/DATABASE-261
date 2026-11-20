/* UI adapter for the marketplace API. See API_CONTRACT.md for request shapes. */
const API = '/api';
const state = {
  products: [], categories: [], sellers: [], buyers: [], shippingCompanies: [],
  cart: [], addresses: [], vouchers: [], selectedBuyerId: '', currentSellerId: '', view: 'buyer', searchTimers: {}
};
const $ = (selector, root = document) => root.querySelector(selector);
const money = value => value == null ? '—' : new Intl.NumberFormat('vi-VN').format(Number(value)) + ' ₫';
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const field = (row, camel, pascal) => row?.[camel] ?? row?.[pascal];
const first = (row, ...names) => names.map(name => row?.[name]).find(value => value !== undefined && value !== null);
const rows = data => Array.isArray(data) ? data : (data?.items || data?.products || data?.results || []);

function normalizeVariant(row) {
  return {
    variantId: field(row, 'variantId', 'Variant_ID'), productId: field(row, 'productId', 'Product_ID'),
    variantName: field(row, 'variantName', 'Variant_Name') || 'Mặc định',
    currentPrice: Number(field(row, 'currentPrice', 'Current_Price') || 0),
    stockQuantity: Number(field(row, 'stockQuantity', 'Stock_Quantity') || 0)
  };
}
function normalizeProduct(row) {
  let imageUrls = field(row, 'imageUrls', 'Image_Urls') ?? field(row, 'images', 'Images') ?? [];
  if (typeof imageUrls === 'string') imageUrls = imageUrls.split('|').map(url => url.trim()).filter(Boolean);
  if (!Array.isArray(imageUrls)) imageUrls = [];
  const variants = field(row, 'variants', 'Variants') ?? [];
  return {
    productId: field(row, 'productId', 'Product_ID'),
    productName: field(row, 'productName', 'Product_Name') ?? field(row, 'name', 'Name') ?? '',
    description: field(row, 'description', 'Description') || '',
    averageRating: field(row, 'averageRating', 'Average_Rating'),
    categoryId: field(row, 'categoryId', 'Category_ID'), categoryName: field(row, 'categoryName', 'Category_Name') || '',
    sellerId: field(row, 'sellerId', 'Seller_ID'), sellerUsername: field(row, 'sellerUsername', 'Seller_Username') || '',
    shopName: field(row, 'shopName', 'Shop_Name') || '',
    variantCount: Number(field(row, 'variantCount', 'Variant_Count') || variants.length || 0),
    lowStockVariantCount: Number(field(row, 'lowStockVariantCount', 'Low_Stock_Variant_Count') || 0),
    minPrice: field(row, 'minPrice', 'Min_Price'), maxPrice: field(row, 'maxPrice', 'Max_Price'),
    totalStock: Number(field(row, 'totalStock', 'Total_Stock') || 0), imageUrls,
    variants: Array.isArray(variants) ? variants.map(normalizeVariant) : []
  };
}
async function api(path, options = {}) {
  const headers = { ...(options.body instanceof FormData ? {} : {'Content-Type':'application/json'}), ...(options.headers || {}) };
  const response = await fetch(API + path, { ...options, headers });
  const contentType = response.headers.get('content-type') || '';
  const body = contentType.includes('application/json') ? await response.json() : await response.text();
  if (!response.ok) {
    const message = typeof body === 'string' ? body : (body.message || body.error || body.detail || `Yêu cầu thất bại (${response.status})`);
    throw new Error(message);
  }
  return body;
}
function notify(message, error = false) {
  const toast = $('#toast'); toast.textContent = message; toast.classList.toggle('error', error); toast.classList.add('show');
  clearTimeout(notify.timer); notify.timer = setTimeout(() => toast.classList.remove('show'), 4000);
}
function imageList(value) {
  if (Array.isArray(value)) return value.filter(Boolean);
  return String(value || '').split('|').map(url => url.trim()).filter(Boolean);
}
function imageMarkup(url, alt = '') {
  return /^https?:\/\//i.test(url || '') ? `<img src="${esc(url)}" alt="${esc(alt)}" loading="lazy" onerror="this.style.display='none'">` : '';
}
function priceLabel(product) {
  if (product.variants.length) {
    const prices = product.variants.map(v => v.currentPrice).filter(price => price > 0);
    if (prices.length) {
      const min = Math.min(...prices), max = Math.max(...prices);
      return min === max ? money(min) : `${money(min)} – ${money(max)}`;
    }
  }
  if (product.minPrice != null) return Number(product.minPrice) === Number(product.maxPrice) ? money(product.minPrice) : `${money(product.minPrice)} – ${money(product.maxPrice)}`;
  return 'Chưa có giá';
}

function renderBuyerProducts() {
  const term = $('#buyer-search').value.trim().toLocaleLowerCase('vi');
  const category = $('#buyer-category').value;
  let products = state.products.filter(p => (!term || `${p.productName} ${p.shopName}`.toLocaleLowerCase('vi').includes(term)) && (!category || String(p.categoryId) === category));
  const sort = $('#buyer-sort').value;
  if (sort === 'price-asc' || sort === 'price-desc') products.sort((a,b) => (Number(a.minPrice || a.variants[0]?.currentPrice || 0) - Number(b.minPrice || b.variants[0]?.currentPrice || 0)) * (sort === 'price-asc' ? 1 : -1));
  if (sort === 'rating-desc') products.sort((a,b) => Number(b.averageRating || 0) - Number(a.averageRating || 0));
  $('#buyer-result-count').textContent = `${products.length} sản phẩm`;
  $('#buyer-products').innerHTML = products.length ? products.map(p => {
    const image = imageList(p.imageUrls)[0];
    const stock = p.totalStock ?? p.variants.reduce((sum,v) => sum + v.stockQuantity, 0);
    return `<article class="store-product-card">
      <button class="store-product-open" data-product-detail="${esc(p.productId)}" aria-label="Xem ${esc(p.productName)}">
        <div class="store-product-image">${image ? imageMarkup(image,p.productName) : '<span class="image-placeholder">◇</span>'}<span class="image-count">${imageList(p.imageUrls).length ? `${imageList(p.imageUrls).length} ảnh` : 'Sản phẩm'}</span></div>
        <div class="store-product-body"><span class="category-pill">${esc(p.categoryName || 'Sản phẩm')}</span><h3>${esc(p.productName)}</h3><div class="store-price">${priceLabel(p)}</div><div class="store-product-meta"><span>${esc(p.shopName || 'Shop')}</span><span class="rating">${p.averageRating == null ? 'Chưa có đánh giá' : `★ ${Number(p.averageRating).toFixed(2)}`}</span></div><div class="stock-caption">${stock > 0 ? `Còn ${stock} sản phẩm` : 'Tạm hết hàng'}</div></div>
      </button><button class="button button-primary card-buy" data-product-detail="${esc(p.productId)}" ${stock <= 0 ? 'disabled' : ''}>Chọn mua</button>
    </article>`;
  }).join('') : '<div class="empty-catalog">Không tìm thấy sản phẩm phù hợp.</div>';
}
function sellerProductRows(products) {
  if (!products.length) return '<tr><td colspan="7" class="empty-state">Không tìm thấy sản phẩm phù hợp.</td></tr>';
  return products.map(p => {
    const image = imageList(p.imageUrls)[0];
    const low = p.variants.length ? p.variants.some(v => v.stockQuantity <= 10) : p.lowStockVariantCount > 0;
    return `<tr><td><div class="product-cell"><div class="product-thumb">${image ? imageMarkup(image,p.productName) : '◇'}</div><div><div class="product-name">${esc(p.productName)}</div><div class="product-id">SP-${String(p.productId).padStart(4,'0')} · ${p.variantCount} phân loại</div></div></div></td>
      <td><span class="category-pill">${esc(p.categoryName || 'Chưa phân loại')}</span></td><td><div class="shop-name">${esc(p.shopName || p.sellerUsername || '—')}</div></td>
      <td class="price">${priceLabel(p)}</td><td><span class="stock ${low ? 'low' : ''}">${Number(p.totalStock || 0)}</span></td>
      <td class="rating">${p.averageRating == null ? '—' : `★ ${Number(p.averageRating).toFixed(2)}`}</td>
      <td><div class="actions"><button class="action-button edit" data-edit-product="${esc(p.productId)}">Sửa</button><button class="action-button delete" data-delete-product="${esc(p.productId)}">Xóa</button></div></td></tr>`;
  }).join('');
}
function renderSellerProducts() {
  const term = $('#seller-search').value.trim().toLocaleLowerCase('vi');
  const category = $('#seller-category').value;
  let products = state.products.filter(p => (!term || `${p.productName} ${p.shopName}`.toLocaleLowerCase('vi').includes(term)) && (!category || String(p.categoryId) === category));
  const [key,dir] = $('#seller-sort').value.split('-'), sign = dir === 'desc' ? -1 : 1;
  const get = p => key === 'price' ? Number(p.minPrice || 0) : key === 'stock' ? Number(p.totalStock || 0) : p.productName.toLocaleLowerCase('vi');
  products.sort((a,b) => (get(a) > get(b) ? 1 : get(a) < get(b) ? -1 : 0) * sign);
  $('#product-rows').innerHTML = sellerProductRows(products);
  $('#visible-products').textContent = products.length;
  $('#total-products').textContent = state.products.length;
  $('#low-stock').textContent = state.products.reduce((sum,p) => sum + (p.variants.length ? p.variants.filter(v => v.stockQuantity <= 10).length : p.lowStockVariantCount), 0);
  $('#result-count').textContent = `${products.length} sản phẩm phù hợp`;
  $('#footer-count').textContent = `${products.length} sản phẩm`;
}
function renderAllProducts() { renderBuyerProducts(); renderSellerProducts(); }

async function loadProducts() {
  const isSellerView = state.view === 'products';
  const term = (isSellerView ? $('#seller-search').value : $('#buyer-search').value).trim();
  const category = isSellerView ? $('#seller-category').value : $('#buyer-category').value;
  const query = new URLSearchParams();
  if (term) query.set('searchTerm', term);
  if (category) query.set('categoryId', category);
  if (isSellerView && state.currentSellerId) query.set('sellerId', state.currentSellerId);
  $('#buyer-result-count').textContent = 'Đang tải sản phẩm...';
  $('#result-count').textContent = 'Đang tải sản phẩm...';
  try {
    const data = await api('/products?' + query.toString());
    state.products = rows(data).map(normalizeProduct);
    renderAllProducts();
  } catch (error) {
    state.products = [];
    $('#buyer-products').innerHTML = `<div class="empty-catalog">${esc(error.message)}<br><small>Backend cần cung cấp GET /api/products.</small></div>`;
    $('#buyer-result-count').textContent = 'Chưa tải được danh mục';
    $('#product-rows').innerHTML = `<tr><td colspan="7" class="empty-state">${esc(error.message)} · Kiểm tra backend API.</td></tr>`;
    $('#result-count').textContent = 'Không tải được danh sách';
  }
}

function fillOptions(selector, items, valueKey, labelKey, firstLabel) {
  const element = $(selector), old = element.value;
  element.innerHTML = `<option value="">${esc(firstLabel)}</option>` + items.map(item => `<option value="${esc(item[valueKey])}">${esc(item[labelKey])}</option>`).join('');
  if (items.some(item => String(item[valueKey]) === old)) element.value = old;
}
async function loadLookups() {
  const tasks = await Promise.allSettled([
    api('/lookups/categories'), api('/lookups/sellers'), api('/lookups/buyers'), api('/lookups/shipping-companies')
  ]);
  if (tasks[0].status === 'fulfilled') state.categories = rows(tasks[0].value).map(x => ({categoryId: field(x,'categoryId','Category_ID'), categoryName: field(x,'categoryName','Category_Name')}));
  if (tasks[1].status === 'fulfilled') state.sellers = rows(tasks[1].value).map(x => ({sellerId: field(x,'sellerId','Seller_ID') ?? field(x,'userId','User_ID'), shopName: field(x,'shopName','Shop_Name')}));
  if (tasks[2].status === 'fulfilled') state.buyers = rows(tasks[2].value).map(x => ({buyerId: field(x,'buyerId','Buyer_ID') ?? field(x,'userId','User_ID'), fullname: field(x,'fullname','Fullname') || field(x,'username','Username')}));
  if (tasks[3].status === 'fulfilled') state.shippingCompanies = rows(tasks[3].value).map(x => ({companyId: field(x,'companyId','Company_ID'), companyName: field(x,'companyName','Company_Name'), estimatedShippingFee: Number(field(x,'estimatedShippingFee','Estimated_Shipping_Fee') || 0)}));
  fillOptions('#buyer-category', state.categories, 'categoryId', 'categoryName', 'Tất cả danh mục');
  fillOptions('#seller-category', state.categories, 'categoryId', 'categoryName', 'Tất cả danh mục');
  fillOptions('#seller-account', state.sellers, 'sellerId', 'shopName', 'Tất cả shop');
  if (!$('#seller-account').value && state.sellers.length) {
    $('#seller-account').value = state.sellers[0].sellerId;
  }
  state.currentSellerId = $('#seller-account').value;
  fillOptions('#product-category', state.categories, 'categoryId', 'categoryName', 'Chọn danh mục');
  fillOptions('#product-seller', state.sellers, 'sellerId', 'shopName', 'Chọn shop');
}

function renderVariantInputs(variants = []) {
  const list = $('#variant-list');
  const values = variants.length ? variants : [{variantName:'Mặc định',currentPrice:'',stockQuantity:0}];
  list.innerHTML = values.map((variant,index) => `<div class="variant-row" data-variant-id="${esc(variant.variantId || '')}">
    <label>Phân loại<input class="variant-name" maxlength="100" required value="${esc(variant.variantName || '')}" placeholder="Ví dụ: Đen / 128GB"></label>
    <label>Giá bán (₫)<input class="variant-price" type="number" min="1" max="1000000000" step="1" required value="${esc(variant.currentPrice ?? '')}" placeholder="Giá theo schema"></label>
    <label>Tồn kho<input class="variant-stock" type="number" min="0" step="1" required value="${esc(variant.stockQuantity ?? 0)}"></label>
    <button class="icon-button remove-variant" type="button" aria-label="Bỏ phân loại">×</button>
  </div>`).join('');
}
function renderImageInputs(urls = ['']) {
  const values = urls.length ? urls : [''];
  $('#image-url-list').innerHTML = values.map((url,index) => `<div class="image-url-row"><div class="image-preview">${imageMarkup(url,`Ảnh ${index+1}`)}${url ? '' : '<span>▧</span>'}</div><input class="image-url-input" type="url" maxlength="400" value="${esc(url)}" placeholder="https://example.com/image.jpg" aria-label="Đường dẫn ảnh ${index+1}"><button class="icon-button remove-image" type="button" aria-label="Bỏ ảnh">×</button></div>`).join('');
}
async function openProductForm(product = null) {
  $('#product-form').reset(); $('#product-id').value = product?.productId || '';
  $('#dialog-title').textContent = product ? 'Sửa sản phẩm' : 'Thêm sản phẩm';
  let detail = product;
  if (product?.productId) {
    try { detail = normalizeProduct(await api(`/products/${product.productId}`)); }
    catch (error) { notify('Không tải được biến thể chi tiết: ' + error.message, true); }
  }
  $('#product-name').value = detail?.productName || '';
  $('#product-description').value = detail?.description || '';
  $('#product-category').value = detail?.categoryId || '';
  $('#product-seller').value = detail?.sellerId || state.currentSellerId || state.sellers[0]?.sellerId || '';
  renderVariantInputs(detail?.variants || []);
  renderImageInputs(imageList(detail?.imageUrls));
  $('#product-dialog').showModal();
}
function collectVariants() {
  return [...document.querySelectorAll('.variant-row')].map(row => ({
    variantId: row.dataset.variantId ? Number(row.dataset.variantId) : undefined,
    variantName: $('.variant-name',row).value.trim(), currentPrice: Number($('.variant-price',row).value), stockQuantity: Number($('.variant-stock',row).value)
  }));
}
async function saveProduct(event) {
  event.preventDefault();
  const productId = $('#product-id').value;
  const variants = collectVariants();
  const imageUrls = [...new Set([...document.querySelectorAll('.image-url-input')].map(input => input.value.trim()).filter(Boolean))];
  const payload = { name: $('#product-name').value.trim(), description: $('#product-description').value.trim() || null,
    categoryId: Number($('#product-category').value), sellerId: Number($('#product-seller').value), variants, imageUrls };
  if (payload.name.length < 2 || payload.name.length > 200) return notify('Tên sản phẩm cần từ 2 đến 200 ký tự.', true);
  if (!payload.categoryId || !payload.sellerId) return notify('Hãy chọn danh mục và người bán.', true);
  if (!variants.length) return notify('Mỗi sản phẩm cần ít nhất một phân loại.', true);
  const names = variants.map(v => v.variantName.toLocaleLowerCase('vi'));
  if (variants.some(v => !v.variantName || v.variantName.length > 100) || new Set(names).size !== names.length) return notify('Tên phân loại không được trống hoặc trùng nhau.', true);
  if (variants.some(v => !Number.isInteger(v.currentPrice) || v.currentPrice < 1 || v.currentPrice > 1000000000)) return notify('Giá bán mỗi phân loại phải là số nguyên từ 1 đến 1.000.000.000 ₫.', true);
  if (variants.some(v => !Number.isInteger(v.stockQuantity) || v.stockQuantity < 0)) return notify('Tồn kho phải là số nguyên không âm.', true);
  if (imageUrls.some(url => url.length > 400 || !/^https?:\/\//i.test(url))) return notify('URL ảnh phải bắt đầu bằng http:// hoặc https://, tối đa 400 ký tự.', true);
  const button = $('#save-product'); button.disabled = true; button.textContent = 'Đang lưu...';
  try {
    await api(productId ? `/products/${productId}` : '/products', {method: productId ? 'PUT':'POST', body: JSON.stringify(payload)});
    $('#product-dialog').close(); notify(productId ? 'Đã cập nhật sản phẩm.' : 'Đã thêm sản phẩm.'); await loadProducts();
  } catch (error) { notify(error.message, true); }
  finally { button.disabled = false; button.textContent = 'Lưu sản phẩm'; }
}
async function deleteProduct(id) {
  const product = state.products.find(p => String(p.productId) === String(id));
  if (!product || !confirm(`Xóa “${product.productName}”? Thao tác sẽ bị chặn nếu sản phẩm đã phát sinh dữ liệu liên quan.`)) return;
  try { await api(`/products/${id}`,{method:'DELETE'}); notify('Đã xóa sản phẩm.'); await loadProducts(); }
  catch (error) { notify(error.message,true); }
}

async function openProductDetail(id) {
  $('#detail-content').innerHTML = '<div class="loading-card">Đang tải chi tiết sản phẩm...</div>';
  $('#detail-dialog').showModal();
  try {
    const product = normalizeProduct(await api(`/products/${id}`));
    const variants = product.variants;
    const images = imageList(product.imageUrls);
    $('#detail-content').innerHTML = `<div class="dialog-heading"><div><p class="eyebrow">${esc(product.categoryName || 'SẢN PHẨM')}</p><h2>${esc(product.productName)}</h2></div><button class="icon-button close-detail" type="button" aria-label="Đóng">×</button></div>
      <div class="detail-layout"><div class="detail-image-main">${images[0] ? imageMarkup(images[0],product.productName) : '<span class="image-placeholder">◇</span>'}</div><div class="detail-info"><div class="detail-shop">${esc(product.shopName || 'Shop')} ${product.averageRating == null ? '' : `· <span class="rating">★ ${Number(product.averageRating).toFixed(2)}</span>`}</div><div class="detail-price" id="detail-price">${priceLabel(product)}</div><p class="detail-description">${esc(product.description || 'Chưa có mô tả sản phẩm.')}</p>
      <label>Phân loại<select id="detail-variant" ${variants.length ? '' : 'disabled'}>${variants.map(v => `<option value="${esc(v.variantId)}" data-price="${v.currentPrice}" data-stock="${v.stockQuantity}">${esc(v.variantName)} · ${money(v.currentPrice)} · Còn ${v.stockQuantity}</option>`).join('')}</select></label>
      <label>Số lượng<input id="detail-quantity" type="number" min="1" value="1" ${variants.length ? '' : 'disabled'}></label><p id="detail-stock" class="stock-caption"></p>
      <button class="button button-primary add-to-cart" data-product-id="${esc(product.productId)}" ${variants.length ? '' : 'disabled'}>Thêm vào giỏ hàng</button></div></div>
      ${images.length > 1 ? `<div class="detail-gallery">${images.map((url,i) => `<button type="button" class="gallery-image ${i===0?'selected':''}" data-image-url="${esc(url)}">${imageMarkup(url,`${product.productName} ${i+1}`)}</button>`).join('')}</div>` : ''}`;
    const variantSelect = $('#detail-variant'); updateDetailVariant(variantSelect);
  } catch (error) { $('#detail-content').innerHTML = `<div class="dialog-heading"><h2>Không tải được sản phẩm</h2><button class="icon-button close-detail" type="button">×</button></div><p>${esc(error.message)}</p>`; }
}
function updateDetailVariant(select) {
  if (!select?.selectedOptions?.length) return;
  const option = select.selectedOptions[0], stock = Number(option.dataset.stock), price = Number(option.dataset.price);
  $('#detail-price').textContent = money(price);
  $('#detail-stock').textContent = stock > 0 ? `Còn ${stock} sản phẩm` : 'Tạm hết hàng';
  const quantity = $('#detail-quantity'); quantity.max = stock; quantity.value = stock > 0 ? '1' : '0';
  $('.add-to-cart').disabled = stock <= 0;
}
function addCartItem(productId) {
  const variant = $('#detail-variant')?.selectedOptions[0];
  if (!variant) return notify('Sản phẩm chưa có phân loại để bán.',true);
  const quantity = Number($('#detail-quantity').value), stock = Number(variant.dataset.stock);
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > stock) return notify(`Số lượng phải từ 1 đến ${stock}.`,true);
  const product = state.products.find(p => String(p.productId) === String(productId));
  const variantId = Number(variant.value), existing = state.cart.find(line => line.variantId === variantId);
  if (existing && existing.quantity + quantity > stock) return notify(`Giỏ hàng đã có ${existing.quantity}; tồn kho hiện tại là ${stock}.`,true);
  if (existing) existing.quantity += quantity;
  else state.cart.push({productId:Number(productId), productName:product?.productName || 'Sản phẩm', shopName:product?.shopName || '', variantId,
    variantName:variant.textContent.split(' · ')[0], price:Number(variant.dataset.price), stock, quantity, imageUrl:imageList(product?.imageUrls)[0] || ''});
  updateCartCount(); $('#detail-dialog').close(); notify('Đã thêm sản phẩm vào giỏ hàng.');
}
function updateCartCount() { $('#cart-count').textContent = state.cart.reduce((sum,line) => sum + line.quantity,0); }
function renderCart() {
  const subtotal = state.cart.reduce((sum,line) => sum + line.price*line.quantity,0);
  const buyerOptions = state.buyers.map(b => `<option value="${esc(b.buyerId)}" ${String(b.buyerId)===String(state.selectedBuyerId)?'selected':''}>${esc(b.fullname)} · Buyer #${esc(b.buyerId)}</option>`).join('');
  const lineMarkup = state.cart.length ? state.cart.map(line => `<div class="cart-line"><div class="cart-line-image">${line.imageUrl ? imageMarkup(line.imageUrl,line.productName) : '◇'}</div><div class="cart-line-main"><strong>${esc(line.productName)}</strong><small>${esc(line.variantName)} · ${money(line.price)}</small><div class="quantity-control"><button type="button" data-cart-change="-1" data-variant-id="${line.variantId}">−</button><span>${line.quantity}</span><button type="button" data-cart-change="1" data-variant-id="${line.variantId}">＋</button><button type="button" class="cart-remove" data-cart-remove="${line.variantId}">Bỏ</button></div></div><strong class="cart-line-total">${money(line.price*line.quantity)}</strong></div>`).join('') : '<div class="empty-cart">Giỏ hàng đang trống. Hãy chọn sản phẩm từ cửa hàng.</div>';
  const buyerSelected = state.selectedBuyerId;
  $('#cart-content').innerHTML = `<div class="dialog-heading"><div><p class="eyebrow">GIỎ HÀNG</p><h2>${state.cart.length} dòng hàng</h2></div><button class="icon-button close-cart" type="button">×</button></div>
    <div class="cart-lines">${lineMarkup}</div>
    ${state.cart.length ? `<div class="checkout-area"><h3>Thông tin đặt hàng</h3><form id="checkout-form">
      <label>Tài khoản người mua <select id="checkout-buyer" required><option value="">Chọn Buyer</option>${buyerOptions}</select></label>
      <div class="form-grid"><label>Địa chỉ giao hàng <select id="checkout-address" required ${state.addresses.length?'':'disabled'}><option value="">${state.addresses.length?'Chọn địa chỉ':'Chọn Buyer trước'}</option>${state.addresses.map((a,i)=>`<option value="${i}">${esc([a.street,a.ward,a.district,a.city].join(', '))} · ${esc(a.addressType || 'Home')}</option>`).join('')}</select></label>
      <label>Đơn vị vận chuyển <select id="checkout-company" required><option value="">Chọn đơn vị</option>${state.shippingCompanies.map(c=>`<option value="${esc(c.companyId)}" data-fee="${c.estimatedShippingFee}" ${Number(c.companyId)===Number($('#checkout-company')?.value)?'selected':''}>${esc(c.companyName)}</option>`).join('')}</select></label></div>
      <div class="form-grid"><label>Mã voucher (nếu có) <select id="checkout-voucher" ${state.vouchers.length?'':'disabled'}><option value="">Không dùng voucher</option>${state.vouchers.map(v=>`<option value="${esc(v.voucherCode)}">${esc(v.voucherCode)} · giảm ${esc(v.discountPercent)}%</option>`).join('')}</select></label>
      <label>Thanh toán <select id="checkout-method" required><option value="COD">Thanh toán khi nhận hàng</option><option value="Bank Transfer">Chuyển khoản</option><option value="E-Wallet">Ví điện tử</option><option value="Credit Card">Thẻ tín dụng</option></select></label></div>
      <div class="cart-summary"><div><span>Tạm tính</span><strong>${money(subtotal)}</strong></div><div><span>Phí vận chuyển dự kiến</span><strong id="shipping-fee-label">${money(0)}</strong></div><div class="cart-total"><span>Tổng thanh toán dự kiến</span><strong id="checkout-total">${money(subtotal)}</strong></div></div>
      <button class="button button-primary checkout-submit" type="submit">Đặt hàng</button>
    </form></div>` : ''}`;
  if (buyerSelected && state.addresses.length) $('#checkout-address').value = $('#checkout-address').dataset.selected || '';
}
async function loadBuyerData(buyerId) {
  state.selectedBuyerId = buyerId; state.addresses = []; state.vouchers = [];
  if (!buyerId) { renderCart(); return; }
  const results = await Promise.allSettled([api(`/buyers/${buyerId}/addresses`),api(`/buyers/${buyerId}/vouchers`)]);
  if (results[0].status === 'fulfilled') state.addresses = rows(results[0].value).map(x => ({street:field(x,'street','Street'),ward:field(x,'ward','Ward'),district:field(x,'district','District'),city:field(x,'city','City'),addressType:field(x,'addressType','Address_Type')}));
  if (results[1].status === 'fulfilled') state.vouchers = rows(results[1].value).map(x => ({voucherCode:field(x,'voucherCode','Voucher_Code'),discountPercent:field(x,'discountPercent','Discount_Percent')}));
  renderCart();
}
function updateCheckoutTotal() {
  const subtotal = state.cart.reduce((sum,line) => sum + line.price*line.quantity,0);
  const fee = Number($('#checkout-company')?.selectedOptions[0]?.dataset.fee || 0);
  if ($('#shipping-fee-label')) $('#shipping-fee-label').textContent = money(fee);
  if ($('#checkout-total')) $('#checkout-total').textContent = money(subtotal + fee);
}
async function submitOrder(event) {
  event.preventDefault();
  if (!state.cart.length) return notify('Giỏ hàng đang trống.',true);
  const buyerId = Number($('#checkout-buyer').value), addressValue = $('#checkout-address').value;
  const address = addressValue === '' ? null : state.addresses[Number(addressValue)], companyId = Number($('#checkout-company').value);
  if (!buyerId || !address || !companyId) return notify('Chọn Buyer, địa chỉ giao hàng và đơn vị vận chuyển.',true);
  const button = $('.checkout-submit'); button.disabled = true; button.textContent = 'Đang đặt hàng...';
  const body = {buyerId, address:{street:address.street,ward:address.ward,district:address.district,city:address.city},
    companyId, voucherCode:$('#checkout-voucher').value || null, paymentMethod:$('#checkout-method').value,
    shippingFee:Number($('#checkout-company').selectedOptions[0].dataset.fee || 0),
    items:state.cart.map(line=>({variantId:line.variantId,quantity:line.quantity}))};
  try {
    const result = await api('/orders',{method:'POST',body:JSON.stringify(body)});
    state.cart=[]; updateCartCount(); $('#cart-dialog').close();
    notify(`Đặt hàng thành công${result.orderId || result.Order_ID ? ` · Mã đơn #${result.orderId || result.Order_ID}` : ''}.`);
    await loadProducts();
  } catch (error) { notify(error.message,true); }
  finally { button.disabled=false; button.textContent='Đặt hàng'; }
}

async function loadOrders() {
  if (!state.selectedBuyerId) { $('#orders-rows').innerHTML='<tr><td colspan="6" class="empty-state">Mở giỏ hàng và chọn tài khoản Buyer trước.</td></tr>'; return; }
  try {
    const data=await api(`/buyers/${state.selectedBuyerId}/orders`), orders=rows(data);
    $('#orders-rows').innerHTML=orders.length?orders.map(o=>`<tr><td>#${esc(field(o,'orderId','Order_ID'))}</td><td>${esc(field(o,'orderDate','Order_Date'))}</td><td>${esc(field(o,'itemsSummary','Items_Summary')||'—')}</td><td class="price">${money(field(o,'totalAmount','Total_Amount'))}</td><td>${esc(field(o,'status','Status'))}</td><td>${esc(field(o,'paymentStatus','Payment_Status')||'Chưa thanh toán')}</td></tr>`).join(''):'<tr><td colspan="6" class="empty-state">Tài khoản này chưa có đơn hàng.</td></tr>';
  } catch(error) { $('#orders-rows').innerHTML=`<tr><td colspan="6" class="empty-state">${esc(error.message)}</td></tr>`; }
}
async function loadStats() {
  const minOrders=Number($('#min-orders').value);
  if(!Number.isInteger(minOrders)||minOrders<1)return notify('Số đơn tối thiểu phải là số nguyên từ 1 trở lên.',true);
  try {
    const data=await api('/reports/top-products?minOrders='+minOrders), items=rows(data);
    $('#stats-rows').innerHTML=items.length?items.map(x=>`<tr><td><strong>${esc(field(x,'productName','Product_Name'))}</strong></td><td>${esc(field(x,'categoryName','Category_Name')||'—')}</td><td>${Number(field(x,'orderCount','Order_Count')||0)}</td><td>${Number(field(x,'unitsSold','Units_Sold')||0)}</td><td class="price">${money(field(x,'revenue','Revenue'))}</td></tr>`).join(''):'<tr><td colspan="5" class="empty-state">Chưa có kết quả.</td></tr>';
  } catch(error) { $('#stats-rows').innerHTML=`<tr><td colspan="5" class="empty-state">${esc(error.message)} · Backend cần nối procedure thống kê 2.3.</td></tr>`; }
}

function setView(view) {
  const labels={buyer:['Cửa hàng','KHÁM PHÁ SẢN PHẨM','Chọn sản phẩm và biến thể phù hợp từ các shop.'],products:['Sản phẩm của tôi','KÊNH NGƯỜI BÁN','Quản lý sản phẩm, phân loại, giá bán, tồn kho và ảnh.'],analytics:['Thống kê','HIỆU QUẢ KINH DOANH','Theo dõi kết quả bán hàng từ dữ liệu đơn hàng.'],orders:['Đơn mua của tôi','LỊCH SỬ MUA HÀNG','Theo dõi các đơn hàng của tài khoản Buyer.']};
  state.view=view;
  document.querySelectorAll('.view-panel').forEach(panel=>panel.classList.toggle('hidden',panel.id!==`${view}-panel`));
  document.querySelectorAll('.nav-item').forEach(button=>button.classList.toggle('active',button.dataset.view===view));
  $('#crumb-label').textContent=labels[view][0]; $('#page-title').textContent=labels[view][0]; $('#page-eyebrow').textContent=labels[view][1]; $('#page-subtitle').textContent=labels[view][2];
  $('#cart-button').classList.toggle('hidden',view!=='buyer'); $('#orders-button').classList.toggle('hidden',view!=='buyer'); $('#add-product').classList.toggle('hidden',view!=='products');
  if(view==='orders')loadOrders();
  if(view==='products')loadProducts();
}

document.addEventListener('click',event=>{
  const target=event.target.closest('button'); if(!target)return;
  if(target.dataset.view){setView(target.dataset.view);return;}
  if(target.matches('[data-product-detail]')){openProductDetail(target.dataset.productDetail);return;}
  if(target.matches('.close-detail')){$('#detail-dialog').close();return;}
  if(target.matches('.add-to-cart')){addCartItem(target.dataset.productId);return;}
  if(target.matches('.gallery-image')){$('.detail-image-main').innerHTML=imageMarkup(target.dataset.imageUrl,'Ảnh sản phẩm');document.querySelectorAll('.gallery-image').forEach(x=>x.classList.toggle('selected',x===target));return;}
  if(target.matches('[data-edit-product]')){openProductForm(state.products.find(p=>String(p.productId)===target.dataset.editProduct));return;}
  if(target.matches('[data-delete-product]')){deleteProduct(target.dataset.deleteProduct);return;}
  if(target.matches('[data-cart-remove]')){state.cart=state.cart.filter(line=>line.variantId!==Number(target.dataset.cartRemove));updateCartCount();renderCart();return;}
  if(target.matches('[data-cart-change]')){const line=state.cart.find(x=>x.variantId===Number(target.dataset.variantId));if(line){line.quantity=Math.min(line.stock,line.quantity+Number(target.dataset.cartChange));if(line.quantity<1)state.cart=state.cart.filter(x=>x!==line);}updateCartCount();renderCart();updateCheckoutTotal();return;}
  if(target.matches('.close-cart')){$('#cart-dialog').close();return;}
  if(target.matches('.remove-variant')){if(document.querySelectorAll('.variant-row').length<=1)return notify('Sản phẩm cần ít nhất một phân loại.',true);target.closest('.variant-row').remove();return;}
  if(target.matches('.remove-image')){const urlInputs=[...document.querySelectorAll('.image-url-input')];const index=[...document.querySelectorAll('.remove-image')].indexOf(target);const urls=urlInputs.map(input=>input.value);urls.splice(index,1);renderImageInputs(urls);return;}
  if(target.matches('.close-orders')){$('#orders-dialog').close();return;}
});
$('#buyer-search').addEventListener('input',()=>{clearTimeout(state.searchTimers.buyer);state.searchTimers.buyer=setTimeout(loadProducts,250);});
$('#seller-search').addEventListener('input',()=>{clearTimeout(state.searchTimers.seller);state.searchTimers.seller=setTimeout(loadProducts,250);});
$('#buyer-category').addEventListener('change',loadProducts); $('#seller-category').addEventListener('change',loadProducts);
$('#seller-account').addEventListener('change',event=>{state.currentSellerId=event.target.value;loadProducts();});
$('#buyer-sort').addEventListener('change',renderBuyerProducts); $('#seller-sort').addEventListener('change',renderSellerProducts);
$('#refresh').addEventListener('click',loadProducts); $('#add-product').addEventListener('click',()=>openProductForm());
$('#product-form').addEventListener('submit',saveProduct); $('#close-dialog').addEventListener('click',()=>$('#product-dialog').close()); $('#cancel-dialog').addEventListener('click',()=>$('#product-dialog').close());
$('#add-variant').addEventListener('click',()=>{const variants=collectVariants();variants.push({variantName:'',currentPrice:'',stockQuantity:0});renderVariantInputs(variants);});
$('#add-image-url').addEventListener('click',()=>{const urls=[...document.querySelectorAll('.image-url-input')].map(input=>input.value);urls.push('');renderImageInputs(urls);});
$('#cart-button').addEventListener('click',()=>{$('#cart-dialog').showModal();renderCart();});
$('#orders-button').addEventListener('click',()=>setView('orders')); $('#reload-orders').addEventListener('click',loadOrders);
$('#load-stats').addEventListener('click',loadStats);
$('#buyer-products').addEventListener('click',event=>{if(event.target.matches('.store-product-open'))openProductDetail(event.target.dataset.productDetail);});
$('#detail-content').addEventListener('change',event=>{if(event.target.id==='detail-variant')updateDetailVariant(event.target);});
$('#cart-content').addEventListener('change',event=>{
  if(event.target.id==='checkout-buyer')loadBuyerData(event.target.value);
  if(event.target.id==='checkout-company')updateCheckoutTotal();
});
$('#cart-content').addEventListener('submit',event=>{if(event.target.id==='checkout-form')submitOrder(event);});

(async function init(){await loadLookups();await loadProducts();})();
