import os
import shutil
import json
import zipfile

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PACKAGE_DIR = os.path.join(BASE_DIR, 'tools', 'map', 'USST_Campus_Editor')
ZIP_OUTPUT = os.path.join(BASE_DIR, 'USST_校园地图协作标注包.zip')

print(f"Creating standalone collaboration package in: {PACKAGE_DIR}")
if os.path.exists(PACKAGE_DIR):
    shutil.rmtree(PACKAGE_DIR)
os.makedirs(PACKAGE_DIR, exist_ok=True)

# 1. Copy local tiles
tiles_src = os.path.join(BASE_DIR, 'assets', 'tiles')
tiles_dst = os.path.join(PACKAGE_DIR, 'assets', 'tiles')
print("Copying offline tiles (3.99 MB)...")
shutil.copytree(tiles_src, tiles_dst)

# 2. Copy official map reference
official_map_src = r'C:\Users\prima\Downloads\0d4069206880b19e0734937653711907.png'
official_map_dst = os.path.join(PACKAGE_DIR, '校园官方参考图.png')
if os.path.exists(official_map_src):
    print("Copying official campus guide map...")
    shutil.copy2(official_map_src, official_map_dst)

# 3. Read latest geojson files
with open(os.path.join(BASE_DIR, 'tools', 'map', 'usst_516_buildings.geojson'), 'r', encoding='utf-8') as f:
    bld_json = json.load(f)

with open(os.path.join(BASE_DIR, 'tools', 'map', 'usst_516_roads.geojson'), 'r', encoding='utf-8') as f:
    roads_json = json.load(f)

with open(os.path.join(BASE_DIR, 'tools', 'map', 'usst_516_pois.geojson'), 'r', encoding='utf-8') as f:
    pois_json = json.load(f)

# 4. Generate standalone index.html
html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>USST 校园地图协助标注工具（免安装协作版）</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
    #map {{ width: 100vw; height: 100vh; background: #e2e8f0; }}
    
    .panel {{
      position: absolute; top: 12px; left: 12px; z-index: 1000;
      background: rgba(255, 255, 255, 0.98); backdrop-filter: blur(10px);
      padding: 14px 16px; border-radius: 12px;
      box-shadow: 0 4px 25px rgba(0,0,0,0.18); width: 360px; max-height: 94vh;
      overflow-y: auto; transition: all 0.2s ease;
    }}
    .panel h2 {{ margin: 0 0 6px 0; font-size: 16px; color: #0f172a; display: flex; align-items: center; justify-content: space-between; }}
    
    .tab-bar {{ display: flex; gap: 4px; background: #f1f5f9; padding: 3px; border-radius: 8px; margin: 8px 0; }}
    .tab-btn {{
      flex: 1; padding: 6px 0; border: none; background: transparent; font-size: 13px;
      font-weight: 600; color: #64748b; border-radius: 6px; cursor: pointer; text-align: center;
    }}
    .tab-btn.active {{ background: #fff; color: #2563eb; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }}
    
    .editor-tools {{
      display: flex; flex-direction: column; gap: 8px; margin-top: 10px;
      padding: 10px; background: #f8fafc; border-radius: 8px; border: 1px solid #e2e8f0;
    }}
    .tool-row {{ display: flex; gap: 6px; }}
    .btn {{
      padding: 8px 12px; border-radius: 6px; border: none; font-size: 13px; font-weight: 600;
      cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 6px;
      transition: background 0.15s;
    }}
    .btn-primary {{ background: #2563eb; color: #fff; }}
    .btn-primary:hover {{ background: #1d4ed8; }}
    .btn-purple {{ background: #9333ea; color: #fff; }}
    .btn-purple:hover {{ background: #7e22ce; }}
    .btn-success {{ background: #16a34a; color: #fff; }}
    .btn-success:hover {{ background: #15803d; }}
    .btn-warning {{ background: #f59e0b; color: #fff; }}
    .btn-warning:hover {{ background: #d97706; }}
    .btn-danger {{ background: #ef4444; color: #fff; }}
    .btn-danger:hover {{ background: #dc2626; }}
    .btn-outline {{ background: #fff; border: 1px solid #cbd5e1; color: #334155; }}
    .btn-outline:hover {{ background: #f1f5f9; }}
    
    .status-hint {{
      font-size: 12px; padding: 8px 10px; border-radius: 6px; background: #eff6ff;
      color: #1e40af; border-left: 3px solid #2563eb; line-height: 1.4;
    }}
    
    .search-box {{ margin-top: 6px; display: flex; gap: 6px; }}
    .search-box input {{
      flex: 1; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px; outline: none;
    }}
    .search-box input:focus {{ border-color: #2563eb; }}
    .quick-tags {{ margin-top: 8px; display: flex; flex-wrap: wrap; gap: 4px; }}
    .tag-btn {{
      padding: 3px 6px; font-size: 11px; border-radius: 4px; background: #f1f5f9; border: 1px solid #e2e8f0;
      color: #475569; cursor: pointer;
    }}
    .tag-btn:hover {{ background: #e2e8f0; color: #0f172a; }}

    .modal-overlay {{
      display: none; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
      background: rgba(0,0,0,0.55); z-index: 2000; align-items: center; justify-content: center;
    }}
    .modal-overlay.show {{ display: flex; }}
    .modal-card {{
      background: #fff; border-radius: 12px; width: 420px; max-width: 92vw; padding: 20px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.25);
    }}
    .modal-card h3 {{ margin: 0 0 14px 0; font-size: 16px; color: #0f172a; }}
    .form-group {{ margin-bottom: 12px; }}
    .form-group label {{ display: block; font-size: 12px; font-weight: 600; color: #475569; margin-bottom: 4px; }}
    .form-group input, .form-group select, .form-group textarea {{
      width: 100%; padding: 8px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px;
    }}
    .modal-actions {{ display: flex; justify-content: flex-end; gap: 8px; margin-top: 18px; }}

    .bld-text-label {{
      background: rgba(255, 255, 255, 0.92); border: 1px solid #94a3b8; border-radius: 4px;
      padding: 1px 5px; font-size: 11px; font-weight: bold; color: #1e293b; pointer-events: none;
      box-shadow: 0 1px 3px rgba(0,0,0,0.15); white-space: nowrap;
    }}
    
    .cat-pill {{ display: inline-block; padding: 1px 6px; border-radius: 4px; font-size: 10px; font-weight: 600; color: #fff; margin-left: 4px; }}
    .pill-teaching {{ background: #2563eb; }}
    .pill-dorm {{ background: #db2777; }}
    .pill-dining {{ background: #ea580c; }}
    .pill-sports {{ background: #059669; }}
    .pill-library {{ background: #0284c7; }}
    .pill-service {{ background: #d97706; }}

    /* 参考大图弹窗 */
    #refMapModal .modal-card {{ width: 85vw; max-width: 1100px; height: 85vh; display: flex; flex-direction: column; }}
    #refMapModal img {{ flex: 1; object-fit: contain; width: 100%; min-height: 0; background: #0f172a; border-radius: 8px; }}
  </style>
</head>
<body>

  <div class="panel">
    <h2>
      <span>🏫 USST 地图协作标注器</span>
      <span style="font-size:11px; background:#dcfce7; color:#15803d; padding:2px 6px; border-radius:10px;">离线协作版</span>
    </h2>

    <div class="tab-bar">
      <button class="tab-btn active" id="tabBrowse" onclick="switchMode('browse')">🔍 查阅地图</button>
      <button class="tab-btn" id="tabEdit" onclick="switchMode('edit')">✏️ 标注与描摹</button>
    </div>

    <!-- 查阅模式 -->
    <div id="browsePanel">
      <div class="search-box">
        <input type="text" id="searchInput" placeholder="搜编号(40, 15)或建筑名..." />
        <button class="btn btn-primary" onclick="searchPlace()">查找</button>
      </div>
      <div class="quick-tags">
        <span style="font-size:11px; color:#64748b; line-height:22px;">快捷定位:</span>
        <span class="tag-btn" onclick="quickFly('40')">[40] 一教</span>
        <span class="tag-btn" onclick="quickFly('15')">[15] 三教</span>
        <span class="tag-btn" onclick="quickFly('45')">[45] 格致堂</span>
        <span class="tag-btn" onclick="quickFly('21')">[21] 综合楼</span>
        <span class="tag-btn" onclick="quickFly('20')">[20] 五食</span>
        <span class="tag-btn" onclick="quickFly('K')">[K] 思裴堂</span>
      </div>
      <div style="margin-top:10px; display:flex; flex-direction:column; gap:6px;">
        <label style="cursor:pointer; display:flex; align-items:center; gap:6px; font-size:12px; color:#475569;">
          <input type="checkbox" id="chkPermanentLabels" onchange="togglePermanentLabels(this.checked)" checked />
          <b>🏷️ 常驻显示建筑名称与编号</b>
        </label>
        <button class="btn btn-outline" style="font-size:12px; padding:6px;" onclick="openRefMapModal()">
          🗺️ 点击查看官方校园全景参考图
        </button>
      </div>
    </div>

    <!-- 编辑模式 -->
    <div id="editPanel" style="display:none;">
      <div class="status-hint" id="statusHint">
        💡 <b>标注助手</b>：<br/>
        • 鼠标点击已有建筑可修改属性或拉动黄色角点；<br/>
        • 绘图点错按 <b>Backspace</b> 或 <b>Ctrl+Z</b> 撤销；<br/>
        • 浏览器会自动保存草稿，画完点击下方【导出数据】发回！
      </div>

      <div class="editor-tools">
        <div class="tool-row">
          <button class="btn btn-primary" style="flex:1;" onclick="startDrawPolygon()">
            ➕ 绘制新建筑
          </button>
          <button class="btn btn-purple" style="flex:1;" onclick="startDrawCircle()">
            ⭕ 绘制圆建筑
          </button>
        </div>
        <div class="tool-row">
          <button class="btn btn-outline" style="flex:1;" onclick="startDrawRoad()">
            🚶 绘制新步道 (路线)
          </button>
          <button class="btn btn-outline" style="flex:1;" onclick="openRefMapModal()">
            🗺️ 参考图
          </button>
        </div>
        
        <div class="tool-row" id="drawControlRow" style="display:none; flex-direction:column; gap:6px;">
          <div style="display:flex; gap:6px;">
            <button class="btn btn-warning" style="flex:1;" onclick="undoLastPoint()">
              ↩️ 撤销上一个点
            </button>
            <button class="btn btn-danger" style="flex:1;" onclick="cancelCurrentDrawing()">
              ❌ 取消重画
            </button>
          </div>
          <button class="btn btn-success" style="width:100%;" onclick="finishCurrentDrawing()">
            ✅ 完成绘制并填信息
          </button>
        </div>

        <div style="border-top:1px dashed #cbd5e1; margin:4px 0;"></div>

        <button class="btn btn-success" style="width:100%; padding:10px; font-size:14px;" onclick="exportDeliverable()">
          📤 导出标注数据 (发给发起人)
        </button>
        
        <div style="display:flex; gap:6px;">
          <button class="btn btn-outline" style="flex:1; font-size:11px;" onclick="restoreLocalStorage()">
            🔄 恢复草稿
          </button>
          <button class="btn btn-outline" style="flex:1; font-size:11px;" onclick="clearLocalStorage()">
            🗑️ 清空草稿
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- 编辑属性弹窗 Modal -->
  <div class="modal-overlay" id="editModal">
    <div class="modal-card">
      <h3 id="modalTitle">编辑建筑文本与属性</h3>
      <div class="form-group">
        <label>官方编号 (Code)</label>
        <input type="text" id="inpCode" placeholder="如: 01, A, 15, 40" />
      </div>
      <div class="form-group">
        <label>建筑名称 (Name) *</label>
        <input type="text" id="inpName" placeholder="如: 第七学生公寓, 先进制造大楼" />
      </div>
      <div class="form-group">
        <label>功能类别 (Category)</label>
        <select id="selCategory">
          <option value="teaching">教学科研 (蓝色)</option>
          <option value="dorm">学生宿舍 (粉紫色)</option>
          <option value="dining">食堂餐饮 (橙色)</option>
          <option value="sports">体育场馆 (绿色)</option>
          <option value="library">图书自习 (青色)</option>
          <option value="service">生活服务 (琥珀色)</option>
        </select>
      </div>
      <div class="form-group">
        <label>补充说明 / 别名 (Subtitle)</label>
        <input type="text" id="inpSubtitle" placeholder="如: 原学生发展中心改建" />
      </div>
      <div class="form-group">
        <label>楼层数 (Levels)</label>
        <input type="text" id="inpLevels" placeholder="如: 6" />
      </div>
      <div class="modal-actions">
        <button class="btn btn-outline" onclick="closeModal()">取消</button>
        <button class="btn btn-danger" id="btnDeleteFeature" style="display:none;" onclick="deleteCurrentFeature()">🗑️ 删除建筑</button>
        <button class="btn btn-primary" onclick="submitModal()">确定保存</button>
      </div>
    </div>
  </div>

  <!-- 官方参考图弹窗 -->
  <div class="modal-overlay" id="refMapModal">
    <div class="modal-card">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
        <h3 style="margin:0;">🗺️ 上海理工大学 军工路校区 官方全景指引图</h3>
        <button class="btn btn-outline" style="padding:4px 8px;" onclick="closeRefMapModal()">✖ 关闭</button>
      </div>
      <img src="校园官方参考图.png" alt="官方参考图" />
    </div>
  </div>

  <div id="map"></div>

  <script>
    // 初始内置数据
    let buildingsData = {json.dumps(bld_json, ensure_ascii=False)};
    let roadsData = {json.dumps(roads_json, ensure_ascii=False)};
    let poisData = {json.dumps(pois_json, ensure_ascii=False)};

    // 检查 LocalStorage 是否有保存的草稿
    const savedBuildings = localStorage.getItem('usst_map_buildings');
    const savedRoads = localStorage.getItem('usst_map_roads');
    if (savedBuildings) {{
      try {{
        buildingsData = JSON.parse(savedBuildings);
        console.log('已从 LocalStorage 自动加载本地建筑草稿！');
      }} catch(e) {{}}
    }}
    if (savedRoads) {{
      try {{
        roadsData = JSON.parse(savedRoads);
      }} catch(e) {{}}
    }}

    const campusBounds = L.latLngBounds([31.2840, 121.5430], [31.3030, 121.5640]);

    const map = L.map('map', {{
      center: [31.2935, 121.5490],
      zoom: 17,
      minZoom: 14,
      maxZoom: 21,
      maxBounds: campusBounds.pad(0.15)
    }});

    const localTiles = L.tileLayer('assets/tiles/{{z}}_{{x}}_{{y}}.png', {{
      minZoom: 14,
      maxNativeZoom: 18,
      maxZoom: 21,
      bounds: campusBounds,
      attribution: '本地离线瓦片'
    }}).addTo(map);

    const esriSatellite = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}', {{
      attribution: 'Tiles &copy; Esri World Imagery',
      minZoom: 14,
      maxNativeZoom: 19,
      maxZoom: 21
    }});

    const baseMaps = {{
      "🛰️ Esri 高清遥感卫星图 (描摹基准)": esriSatellite,
      "💾 本地离线街道瓦片": localTiles
    }};
    
    const categoryColors = {{
      'teaching': {{ fill: '#3b82f6', border: '#1d4ed8', label: '教学科研', pill: 'pill-teaching' }},
      'dorm':     {{ fill: '#ec4899', border: '#be185d', label: '学生宿舍', pill: 'pill-dorm' }},
      'dining':   {{ fill: '#f97316', border: '#c2410c', label: '食堂餐饮', pill: 'pill-dining' }},
      'sports':   {{ fill: '#10b981', border: '#047857', label: '体育场馆', pill: 'pill-sports' }},
      'library':  {{ fill: '#06b6d4', border: '#0e7490', label: '图书自习', pill: 'pill-library' }},
      'service':  {{ fill: '#f59e0b', border: '#b45309', label: '生活服务', pill: 'pill-service' }}
    }};

    let currentMode = 'browse';
    let showLabels = true;
    let selectedLayer = null;
    let activeVertexMarkers = [];

    let isDrawing = false;
    let drawType = null;
    let drawingPoints = [];
    let drawingMarkers = [];
    let drawingLine = null;
    let circleCenter = null;
    let circlePreview = null;

    let buildingsLayer = null;
    let roadsLayer = null;
    let poisLayer = null;

    function autoSaveDraft() {{
      localStorage.setItem('usst_map_buildings', JSON.stringify(buildingsData));
      localStorage.setItem('usst_map_roads', JSON.stringify(roadsData));
    }}

    function renderAllLayers() {{
      if (buildingsLayer) map.removeLayer(buildingsLayer);
      if (roadsLayer) map.removeLayer(roadsLayer);
      if (poisLayer) map.removeLayer(poisLayer);

      buildingsLayer = L.geoJSON(buildingsData, {{
        style: function(feat) {{
          const cat = feat.properties.category || 'teaching';
          const conf = categoryColors[cat] || categoryColors.teaching;
          const hasName = feat.properties.name && feat.properties.name.length > 0;
          return {{
            fillColor: hasName ? conf.fill : '#94a3b8',
            weight: 1.8,
            opacity: 1,
            color: hasName ? conf.border : '#64748b',
            fillOpacity: hasName ? 0.55 : 0.25
          }};
        }},
        onEachFeature: function(feat, layer) {{
          const p = feat.properties;
          const codePrefix = p.code ? `[${{p.code}}] ` : '';
          const title = codePrefix + (p.name || '未命名建筑');
          
          if (showLabels && p.name) {{
            layer.bindTooltip(title, {{
              permanent: true,
              direction: 'center',
              className: 'bld-text-label'
            }});
          }}

          layer.on('click', function(e) {{
            if (isDrawing) return;
            L.DomEvent.stopPropagation(e);
            if (currentMode === 'edit') {{
              openEditModalForLayer(layer);
            }} else {{
              showPopupForLayer(layer);
            }}
          }});
        }}
      }}).addTo(map);

      roadsLayer = L.geoJSON(roadsData, {{
        style: function(feat) {{
          const hw = feat.properties.highway;
          let color = '#ea580c', weight = 2.5, dash = null;
          if (hw === 'footway' || hw === 'pedestrian') {{ color = '#059669'; weight = 2; dash = '3, 4'; }}
          else if (hw === 'steps') {{ color = '#ec4899'; weight = 3; dash = '1, 3'; }}
          else if (hw === 'cycleway') {{ color = '#0284c7'; weight = 2; }}
          return {{ color: color, weight: weight, opacity: 0.85, dashArray: dash }};
        }},
        onEachFeature: function(feat, layer) {{
          layer.on('click', function(e) {{
            if (isDrawing) return;
            L.DomEvent.stopPropagation(e);
            layer.bindPopup(`<b>道路: ${{feat.properties.name || '内部步道'}}</b><br/>类型: ${{feat.properties.highway}}`).openPopup();
          }});
        }}
      }}).addTo(map);

      poisLayer = L.geoJSON(poisData, {{
        pointToLayer: function(feat, latlng) {{
          const isGate = feat.properties.amenity === 'gate' || feat.properties.name.includes('门');
          const m = L.circleMarker(latlng, {{
            radius: isGate ? 7 : 5,
            fillColor: isGate ? '#dc2626' : '#6366f1',
            color: '#ffffff', weight: 2, fillOpacity: 0.95
          }});
          m.bindPopup(`<b>${{feat.properties.name}}</b>${{feat.properties.code ? ' (' + feat.properties.code + ')' : ''}}`);
          return m;
        }}
      }}).addTo(map);
    }}

    renderAllLayers();
    L.control.layers(baseMaps, {{ "🏫 建筑轮廓": buildingsLayer, "🚶 步道路网": roadsLayer }}, {{ position: 'topright' }}).addTo(map);

    function showPopupForLayer(layer) {{
      const p = layer.feature.properties;
      const cat = p.category || 'teaching';
      const conf = categoryColors[cat] || categoryColors.teaching;
      const codePrefix = p.code ? `[${{p.code}}] ` : '';
      let html = `<div style="min-width:180px;">`;
      html += `<b style="font-size:14px; color:#0f172a;">${{codePrefix}}${{p.name || '未命名建筑'}}</b>`;
      html += `<span class="cat-pill ${{conf.pill}}">${{conf.label}}</span><br/>`;
      if (p.subtitle) html += `<div style="color:#475569; font-size:12px; margin:4px 0;">${{p.subtitle}}</div>`;
      if (p.levels) html += `<span style="color:#64748b; font-size:11px;">楼层: ${{p.levels}} 层</span>`;
      html += `</div>`;
      layer.bindPopup(html).openPopup();
    }}

    window.switchMode = function(m) {{
      currentMode = m;
      document.getElementById('tabBrowse').className = 'tab-btn' + (m === 'browse' ? ' active' : '');
      document.getElementById('tabEdit').className = 'tab-btn' + (m === 'edit' ? ' active' : '');
      document.getElementById('browsePanel').style.display = m === 'browse' ? 'block' : 'none';
      document.getElementById('editPanel').style.display = m === 'edit' ? 'block' : 'none';
      cancelVertexEditing();
      cancelCurrentDrawing();
      if (m === 'edit') {{
        map.addLayer(esriSatellite);
      }}
    }};

    window.togglePermanentLabels = function(show) {{
      showLabels = show;
      renderAllLayers();
    }};

    window.searchPlace = function() {{
      const q = document.getElementById('searchInput').value.trim();
      if (!q) return;
      let matchedLayer = null;
      buildingsLayer.eachLayer(layer => {{
        const p = layer.feature.properties;
        if ((p.name && p.name.includes(q)) || (p.code && p.code.toLowerCase() === q.toLowerCase()) || (p.subtitle && p.subtitle.includes(q))) {{
          matchedLayer = layer;
        }}
      }});
      if (matchedLayer) {{
        map.fitBounds(matchedLayer.getBounds(), {{ maxZoom: 19 }});
        showPopupForLayer(matchedLayer);
      }} else {{
        alert('未在现有数据中找到: ' + q);
      }}
    }};

    window.quickFly = function(code) {{
      document.getElementById('searchInput').value = code;
      searchPlace();
    }};

    window.openRefMapModal = function() {{
      document.getElementById('refMapModal').className = 'modal-overlay show';
    }};
    window.closeRefMapModal = function() {{
      document.getElementById('refMapModal').className = 'modal-overlay';
    }};

    // 绘图功能
    window.startDrawPolygon = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'polygon';
      drawingPoints = [];
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '📍 <b>正在绘制多边形建筑</b>：依次点击拐角点打点；按 <b>Backspace</b> 可随时撤销上一个点。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    window.startDrawCircle = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'circle';
      circleCenter = null;
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '⭕ <b>正在绘制圆形建筑</b>：第 1 次点击：确定圆心；移动鼠标预览；第 2 次点击：确定半径边缘。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    window.startDrawRoad = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'road';
      drawingPoints = [];
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '🚶 <b>正在绘制步道</b>：沿道路走向依次打点；按 <b>Backspace</b> 撤销上一个点。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    window.undoLastPoint = function() {{
      if (!isDrawing) return;
      if (drawType === 'circle') {{
        circleCenter = null;
        if (circlePreview) map.removeLayer(circlePreview);
        circlePreview = null;
        if (drawingMarkers.length > 0) map.removeLayer(drawingMarkers.pop());
        document.getElementById('statusHint').innerHTML = '⭕ <b>已重置圆心</b>：请重新点击确定圆心。';
        return;
      }}
      if (drawingPoints.length === 0) return;
      drawingPoints.pop();
      const lastMarker = drawingMarkers.pop();
      if (lastMarker) map.removeLayer(lastMarker);
      updateDrawingVisuals();
      document.getElementById('statusHint').innerHTML = `↩️ <b>已撤销上一个点</b>，当前剩余 ${{drawingPoints.length}} 个点。`;
    }};

    window.addEventListener('keydown', function(e) {{
      if (isDrawing && (e.key === 'Backspace' || (e.ctrlKey && e.key.toLowerCase() === 'z'))) {{
        if (document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA')) return;
        e.preventDefault();
        undoLastPoint();
      }}
    }});

    map.on('click', function(e) {{
      if (!isDrawing) return;
      const lat = e.latlng.lat;
      const lng = e.latlng.lng;

      if (drawType === 'circle') {{
        if (!circleCenter) {{
          circleCenter = e.latlng;
          const cm = L.circleMarker([lat, lng], {{ radius: 5, color: '#9333ea', fillColor: '#fff', fillOpacity: 1 }}).addTo(map);
          drawingMarkers.push(cm);
          document.getElementById('statusHint').innerHTML = '⭕ <b>圆心已定</b>：移动鼠标观察大小，在圆周边缘点击确定半径。';
        }} else {{
          const radiusMeters = circleCenter.distanceTo(e.latlng);
          const circlePolyCoords = generateCirclePolygon(circleCenter, radiusMeters, 24);
          openNewModalForDrawnPolygon(circlePolyCoords);
        }}
        return;
      }}

      drawingPoints.push([lng, lat]);
      const m = L.circleMarker([lat, lng], {{ radius: 4, color: '#ef4444', fillColor: '#fff', fillOpacity: 1 }}).addTo(map);
      drawingMarkers.push(m);
      updateDrawingVisuals();
      document.getElementById('statusHint').innerHTML = `📍 已记录 ${{drawingPoints.length}} 个拐角点 (点错按 Backspace 撤销)`;
    }});

    map.on('mousemove', function(e) {{
      if (!isDrawing || drawType !== 'circle' || !circleCenter) return;
      const radiusMeters = circleCenter.distanceTo(e.latlng);
      if (circlePreview) map.removeLayer(circlePreview);
      circlePreview = L.circle(circleCenter, {{
        radius: radiusMeters, color: '#9333ea', weight: 2, fillColor: '#c084fc', fillOpacity: 0.35, dashArray: '4, 4'
      }}).addTo(map);
    }});

    function generateCirclePolygon(center, radiusMeters, sides = 24) {{
      const coords = [];
      const dLat = radiusMeters / 111319.5;
      const dLng = radiusMeters / (111319.5 * Math.cos(center.lat * Math.PI / 180));
      for (let i = 0; i < sides; i++) {{
        const theta = (i / sides) * 2 * Math.PI;
        const lat = center.lat + dLat * Math.sin(theta);
        const lng = center.lng + dLng * Math.cos(theta);
        coords.push([Number(lng.toFixed(7)), Number(lat.toFixed(7))]);
      }}
      coords.push(coords[0]);
      return coords;
    }}

    function updateDrawingVisuals() {{
      if (drawingLine) map.removeLayer(drawingLine);
      const latlngs = drawingPoints.map(p => [p[1], p[0]]);
      if (drawType === 'polygon' && latlngs.length >= 3) {{
        drawingLine = L.polygon(latlngs, {{ color: '#2563eb', weight: 2, fillOpacity: 0.35, dashArray: '4, 4' }}).addTo(map);
      }} else if (latlngs.length >= 2) {{
        drawingLine = L.polyline(latlngs, {{ color: '#16a34a', weight: 3, dashArray: '4, 4' }}).addTo(map);
      }}
    }}

    function clearDrawingVisuals() {{
      drawingMarkers.forEach(m => map.removeLayer(m));
      drawingMarkers = [];
      if (drawingLine) map.removeLayer(drawingLine);
      drawingLine = null;
      if (circlePreview) map.removeLayer(circlePreview);
      circlePreview = null;
      circleCenter = null;
    }}

    window.cancelCurrentDrawing = function() {{
      isDrawing = false;
      drawType = null;
      drawingPoints = [];
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'none';
      document.getElementById('statusHint').innerHTML = '💡 <b>编辑模式已就绪</b>：点击已有建筑修改，或点击上方按钮新增。';
      map.getContainer().style.cursor = '';
    }};

    window.finishCurrentDrawing = function() {{
      if (drawType === 'polygon' && drawingPoints.length < 3) {{
        alert('多边形至少需要 3 个拐角点！');
        return;
      }}
      if (drawType === 'road' && drawingPoints.length < 2) {{
        alert('步道线至少需要 2 个连接点！');
        return;
      }}

      if (drawType === 'polygon') {{
        openNewModalForDrawnPolygon(drawingPoints);
      }} else if (drawType === 'road') {{
        const newRoad = {{
          type: 'Feature',
          id: 'manual/road_' + Date.now(),
          properties: {{
            id: 'road_' + Date.now(),
            name: '新增校园步道',
            highway: 'footway',
            foot: 'yes',
            bicycle: 'yes'
          }},
          geometry: {{
            type: 'LineString',
            coordinates: [...drawingPoints]
          }}
        }};
        roadsData.features.push(newRoad);
        cancelCurrentDrawing();
        autoSaveDraft();
        renderAllLayers();
        alert('✅ 新步道已添加！');
      }}
    }};

    let editingFeature = null;
    let isCreatingNew = false;
    let pendingCoords = null;

    function openNewModalForDrawnPolygon(coords) {{
      isCreatingNew = true;
      editingFeature = null;
      pendingCoords = coords;

      document.getElementById('modalTitle').innerText = '➕ 为新绘制建筑添加信息';
      document.getElementById('inpCode').value = '';
      document.getElementById('inpName').value = '';
      document.getElementById('selCategory').value = 'teaching';
      document.getElementById('inpSubtitle').value = '';
      document.getElementById('inpLevels').value = '4';
      document.getElementById('btnDeleteFeature').style.display = 'none';

      document.getElementById('editModal').className = 'modal-overlay show';
    }}

    function openEditModalForLayer(layer) {{
      isCreatingNew = false;
      selectedLayer = layer;
      editingFeature = layer.feature;
      const p = editingFeature.properties;

      document.getElementById('modalTitle').innerText = '✏️ 修改建筑属性: ' + (p.name || '未命名建筑');
      document.getElementById('inpCode').value = p.code || '';
      document.getElementById('inpName').value = p.name || '';
      document.getElementById('selCategory').value = p.category || 'teaching';
      document.getElementById('inpSubtitle').value = p.subtitle || '';
      document.getElementById('inpLevels').value = p.levels || '';
      document.getElementById('btnDeleteFeature').style.display = 'inline-block';

      document.getElementById('editModal').className = 'modal-overlay show';
      enableVertexEditing(layer);
    }}

    window.closeModal = function() {{
      document.getElementById('editModal').className = 'modal-overlay';
    }};

    window.submitModal = function() {{
      const name = document.getElementById('inpName').value.trim();
      if (!name) {{
        alert('请至少输入建筑名称！');
        return;
      }}
      const code = document.getElementById('inpCode').value.trim();
      const cat = document.getElementById('selCategory').value;
      const subtitle = document.getElementById('inpSubtitle').value.trim();
      const levels = document.getElementById('inpLevels').value.trim();

      if (isCreatingNew) {{
        const ring = [...pendingCoords];
        if (ring[0][0] !== ring[ring.length-1][0] || ring[0][1] !== ring[ring.length-1][1]) {{
          ring.push(ring[0]);
        }}
        const newFeat = {{
          type: 'Feature',
          id: 'manual/' + (code ? code : Date.now()),
          properties: {{
            id: 'manual_' + Date.now(),
            code: code,
            name: name,
            category: cat,
            subtitle: subtitle,
            levels: levels || '4',
            tags: {{ name: name, code: code, building: cat }}
          }},
          geometry: {{
            type: 'Polygon',
            coordinates: [ring]
          }}
        }};
        buildingsData.features.push(newFeat);
        cancelCurrentDrawing();
      }} else if (editingFeature) {{
        editingFeature.properties.name = name;
        editingFeature.properties.code = code;
        editingFeature.properties.category = cat;
        editingFeature.properties.subtitle = subtitle;
        editingFeature.properties.levels = levels;
      }}

      closeModal();
      cancelVertexEditing();
      autoSaveDraft();
      renderAllLayers();
      alert('✅ 建筑信息已更新并暂存草稿！');
    }};

    window.deleteCurrentFeature = function() {{
      if (!confirm('确定要删除这栋建筑吗？')) return;
      if (editingFeature) {{
        const idx = buildingsData.features.indexOf(editingFeature);
        if (idx >= 0) buildingsData.features.splice(idx, 1);
      }}
      closeModal();
      cancelVertexEditing();
      autoSaveDraft();
      renderAllLayers();
      alert('已删除该建筑');
    }};

    function enableVertexEditing(layer) {{
      cancelVertexEditing();
      if (!layer || !layer.getLatLngs) return;
      const latlngs = layer.getLatLngs()[0];
      latlngs.forEach((latlng, idx) => {{
        const marker = L.circleMarker(latlng, {{
          radius: 6, color: '#f59e0b', fillColor: '#fff', fillOpacity: 1, weight: 2
        }}).addTo(map);
        marker.on('mousedown', function() {{
          map.dragging.disable();
          map.on('mousemove', onMarkerDrag);
          map.on('mouseup', onMarkerUp);
        }});
        function onMarkerDrag(e) {{
          marker.setLatLng(e.latlng);
          latlngs[idx] = e.latlng;
          layer.setLatLngs([latlngs]);
        }}
        function onMarkerUp(e) {{
          map.dragging.enable();
          map.off('mousemove', onMarkerDrag);
          map.off('mouseup', onMarkerUp);
          const ring = latlngs.map(ll => [ll.lng, ll.lat]);
          ring.push([ring[0][0], ring[0][1]]);
          layer.feature.geometry.coordinates = [ring];
          autoSaveDraft();
        }}
        activeVertexMarkers.push(marker);
      }});
    }}

    function cancelVertexEditing() {{
      activeVertexMarkers.forEach(m => map.removeLayer(m));
      activeVertexMarkers = [];
    }}

    // 导出文件供回传
    window.exportDeliverable = function() {{
      autoSaveDraft();
      const exportPackage = {{
        type: 'USST_MAP_UPDATE_BUNDLE',
        updated_at: new Date().toISOString(),
        buildings: buildingsData,
        roads: roadsData
      }};
      const blob = new Blob([JSON.stringify(exportPackage, null, 2)], {{ type: 'application/json' }});
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'usst_516_map_update_' + new Date().toLocaleDateString().replace(/\\//g, '-') + '.json';
      a.click();
      alert('🎉 导出成功！\\n请将下载好的 JSON 文件微信发回给项目发起人即可！');
    }};

    window.restoreLocalStorage = function() {{
      if (confirm('确定从本地浏览器恢复草稿吗？')) {{
        location.reload();
      }}
    }};

    window.clearLocalStorage = function() {{
      if (confirm('确定清空本地草稿、重置为初始地图吗？')) {{
        localStorage.removeItem('usst_map_buildings');
        localStorage.removeItem('usst_map_roads');
        location.reload();
      }}
    }};
  </script>
</body>
</html>
"""

html_dst = os.path.join(PACKAGE_DIR, '启动地图编辑器.html')
with open(html_dst, 'w', encoding='utf-8') as f:
    f.write(html_content)
print("Saved 启动地图编辑器.html")

# 5. Create README instructions for collaborators
readme_content = """==============================================================
   🏫 上海理工大学（军工路主校区）地图协助标注与描摹说明
==============================================================

你好！非常感谢你协助我们补全军工路 516 号主校区的地图数据！
本工具无需安装任何专业软件（如 QGIS/CAD），也无需配置任何 Python 环境，
只要有一台电脑和一个浏览器（推荐 Edge、Chrome）即可在 5~10 分钟内完成标注。

--------------------------------------------------------------
【快速开始三步走】
--------------------------------------------------------------
1. 打开编辑器：
   双击打开本文件夹内的【启动地图编辑器.html】。

2. 对照与标注：
   • 点击左上角切换到【✏️ 标注与描摹】模式，底图会自动切为高清遥感卫星图；
   • 点击左侧面板中的【🗺️ 参考图】，可以随时对照学校官方的建筑编号（如 01 先进制造大楼、A 第七学生公寓等）；
   • 绘制建筑：点击【➕ 绘制新建筑】，沿着卫星图上的大楼拐角依次点一圈，点击【✅ 完成绘制并填信息】，输入编号和名字；
   • 绘制圆建筑：点击【⭕ 绘制圆建筑】，先点圆心、再点边缘即可一键成型；
   • 绘制步道：点击【🚶 绘制新步道】，沿着能走的路打点即可。
   * 提示：画错时直接按键盘【Backspace】或【Ctrl+Z】即可撤销上一个点！

3. 保存与发回：
   • 你的每一步绘制都会自动暂存在浏览器中，刷新或关闭浏览器也不会丢失进度；
   • 标注完成后，点击左侧面板绿色的【📤 导出标注数据 (发给发起人)】；
   • 浏览器会自动下载一个名为 usst_516_map_update_xxxx.json 的文件；
   • 将这个下载好的 json 文件通过微信 / QQ 发回给发起人即可！大功告成！

感谢你的大力协助！
"""

readme_dst = os.path.join(PACKAGE_DIR, '使用说明(发给协助者看).txt')
with open(readme_dst, 'w', encoding='utf-8') as f:
    f.write(readme_content)
print("Saved 使用说明(发给协助者看).txt")

# 6. Create ZIP archive
print("Compressing package into zip...")
with zipfile.ZipFile(ZIP_OUTPUT, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(PACKAGE_DIR):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, PACKAGE_DIR)
            zipf.write(full_path, arcname=os.path.join('USST_Campus_Editor', rel_path))

zip_size_mb = os.path.getsize(ZIP_OUTPUT) / (1024 * 1024)
print(f"SUCCESS! Created zip: {ZIP_OUTPUT} ({zip_size_mb:.2f} MB)")
