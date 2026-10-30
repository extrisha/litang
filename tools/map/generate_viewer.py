import json

with open('tools/map/usst_516_buildings.geojson', 'r', encoding='utf-8') as f:
    buildings_json = json.load(f)

with open('tools/map/usst_516_roads.geojson', 'r', encoding='utf-8') as f:
    roads_json = json.load(f)

with open('tools/map/usst_516_pois.geojson', 'r', encoding='utf-8') as f:
    pois_json = json.load(f)

html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>USST 516 校园地图与交互式标注编辑器</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
    #map {{ width: 100vw; height: 100vh; background: #e2e8f0; }}
    
    /* 左侧主控制面板 */
    .panel {{
      position: absolute; top: 12px; left: 12px; z-index: 1000;
      background: rgba(255, 255, 255, 0.98); backdrop-filter: blur(10px);
      padding: 14px 16px; border-radius: 12px;
      box-shadow: 0 4px 25px rgba(0,0,0,0.18); width: 360px; max-height: 94vh;
      overflow-y: auto; transition: all 0.2s ease;
    }}
    .panel h2 {{ margin: 0 0 6px 0; font-size: 16px; color: #0f172a; display: flex; align-items: center; justify-content: space-between; }}
    
    /* 模式切换 Tabs */
    .tab-bar {{ display: flex; gap: 4px; background: #f1f5f9; padding: 3px; border-radius: 8px; margin: 8px 0; }}
    .tab-btn {{
      flex: 1; padding: 6px 0; border: none; background: transparent; font-size: 13px;
      font-weight: 600; color: #64748b; border-radius: 6px; cursor: pointer; text-align: center;
    }}
    .tab-btn.active {{ background: #fff; color: #2563eb; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }}
    
    /* 绘图编辑工具条 */
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
    .btn-danger {{ background: #ef4444; color: #fff; }}
    .btn-danger:hover {{ background: #dc2626; }}
    .btn-outline {{ background: #fff; border: 1px solid #cbd5e1; color: #334155; }}
    .btn-outline:hover {{ background: #f1f5f9; }}
    .btn-active {{ background: #fef08a !important; color: #854d0e !important; border: 2px solid #eab308 !important; }}
    
    /* 状态指示与提示 */
    .status-hint {{
      font-size: 12px; padding: 8px 10px; border-radius: 6px; background: #eff6ff;
      color: #1e40af; border-left: 3px solid #2563eb; line-height: 1.4;
    }}
    
    /* 搜索框与标签 */
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

    /* 编辑弹窗 Modal */
    .modal-overlay {{
      display: none; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
      background: rgba(0,0,0,0.45); z-index: 2000; align-items: center; justify-content: center;
    }}
    .modal-overlay.show {{ display: flex; }}
    .modal-card {{
      background: #fff; border-radius: 12px; width: 400px; max-width: 90vw; padding: 20px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.25);
    }}
    .modal-card h3 {{ margin: 0 0 14px 0; font-size: 16px; color: #0f172a; }}
    .form-group {{ margin-bottom: 12px; }}
    .form-group label {{ display: block; font-size: 12px; font-weight: 600; color: #475569; margin-bottom: 4px; }}
    .form-group input, .form-group select, .form-group textarea {{
      width: 100%; padding: 8px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px;
    }}
    .modal-actions {{ display: flex; justify-content: flex-end; gap: 8px; margin-top: 18px; }}

    /* 常驻文字标签 */
    .bld-text-label {{
      background: rgba(255, 255, 255, 0.92); border: 1px solid #94a3b8; border-radius: 4px;
      padding: 1px 5px; font-size: 11px; font-weight: bold; color: #1e293b; pointer-events: none;
      box-shadow: 0 1px 3px rgba(0,0,0,0.15); white-space: nowrap;
    }}
    
    /* 类别徽章 */
    .cat-pill {{ display: inline-block; padding: 1px 6px; border-radius: 4px; font-size: 10px; font-weight: 600; color: #fff; margin-left: 4px; }}
    .pill-teaching {{ background: #2563eb; }}
    .pill-dorm {{ background: #db2777; }}
    .pill-dining {{ background: #ea580c; }}
    .pill-sports {{ background: #059669; }}
    .pill-library {{ background: #0284c7; }}
    .pill-service {{ background: #d97706; }}
  </style>
</head>
<body>

  <!-- 左侧主面板 -->
  <div class="panel">
    <h2>
      <span>🏫 USST 516 校园地图</span>
      <span style="font-size:12px; color:#16a34a; font-weight:bold;">可深度放大至21级</span>
    </h2>

    <!-- 模式切换 -->
    <div class="tab-bar">
      <button class="tab-btn active" id="tabBrowse" onclick="switchMode('browse')">🔍 查阅与搜索</button>
      <button class="tab-btn" id="tabEdit" onclick="switchMode('edit')">✏️ 标注与编辑</button>
    </div>

    <!-- 浏览模式面板 -->
    <div id="browsePanel">
      <div class="search-box">
        <input type="text" id="searchInput" placeholder="搜编号(40, 15, K)或建筑名..." />
        <button class="btn btn-primary" onclick="searchPlace()">查找</button>
      </div>
      <div class="quick-tags">
        <span style="font-size:11px; color:#64748b; margin-right:2px; line-height:22px;">快捷定位:</span>
        <span class="tag-btn" onclick="quickFly('40')">[40] 一教</span>
        <span class="tag-btn" onclick="quickFly('15')">[15] 三教</span>
        <span class="tag-btn" onclick="quickFly('45')">[45] 格致堂</span>
        <span class="tag-btn" onclick="quickFly('21')">[21] 综合楼</span>
        <span class="tag-btn" onclick="quickFly('20')">[20] 五食</span>
        <span class="tag-btn" onclick="quickFly('60')">[60] 二食</span>
        <span class="tag-btn" onclick="quickFly('K')">[K] 思裴堂</span>
      </div>
      <div style="margin-top:10px; font-size:12px; color:#475569;">
        <label style="cursor:pointer; display:flex; align-items:center; gap:6px;">
          <input type="checkbox" id="chkPermanentLabels" onchange="togglePermanentLabels(this.checked)" checked />
          <b>🏷️ 常驻显示建筑名称与编号</b>
        </label>
      </div>
    </div>

    <!-- 编辑模式面板 -->
    <div id="editPanel" style="display:none;">
      <div class="status-hint" id="statusHint">
        💡 <b>编辑模式已开启（已支持放大至 21 级）</b>：<br/>
        1. 鼠标<b>点击任意已有建筑</b>，可直接修改名称、类别或拉动黄色手柄调整轮廓；<br/>
        2. <b>普通多边形</b>：点击【绘制新建筑】，在卫星图上依次点击拐角即可描摹；<br/>
        3. <b>圆形建筑</b>：点击【绘制圆形建筑】，先点圆心、再点半径即可自动生成平滑正多边形。
      </div>

      <div class="editor-tools">
        <div class="tool-row">
          <button class="btn btn-primary" id="btnDrawBld" style="flex:1;" onclick="startDrawPolygon()">
            ➕ 绘制新建筑 (多边形)
          </button>
          <button class="btn btn-purple" id="btnDrawCircle" style="flex:1;" onclick="startDrawCircle()">
            ⭕ 绘制圆形建筑
          </button>
        </div>
        <div class="tool-row">
          <button class="btn btn-outline" id="btnDrawRoad" style="flex:1;" onclick="startDrawRoad()">
            🚶 绘制新步道 (路线)
          </button>
        </div>
        <div class="tool-row" id="drawControlRow" style="display:none;">
          <button class="btn btn-success" style="flex:1;" onclick="finishCurrentDrawing()">
            ✅ 完成绘制并填信息
          </button>
          <button class="btn btn-danger" style="flex:1;" onclick="cancelCurrentDrawing()">
            ❌ 取消本次绘制
          </button>
        </div>
        <div class="tool-row">
          <button class="btn btn-success" style="flex:1;" onclick="saveAllChanges()">
            💾 一键保存所有修改
          </button>
          <button class="btn btn-outline" style="flex:1;" onclick="exportGeoJsonBackup()">
            ⬇️ 导出 GeoJSON 备份
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

  <div id="map"></div>

  <script>
    const buildingsData = {json.dumps(buildings_json, ensure_ascii=False)};
    const roadsData = {json.dumps(roads_json, ensure_ascii=False)};
    const poisData = {json.dumps(pois_json, ensure_ascii=False)};

    const campusBounds = L.latLngBounds([31.2840, 121.5430], [31.3030, 121.5640]);

    // 初始化地图：已将 maxZoom 放大倍率提高到 21 级！
    const map = L.map('map', {{
      center: [31.2935, 121.5490],
      zoom: 17,
      minZoom: 14,
      maxZoom: 21,
      maxBounds: campusBounds.pad(0.15)
    }});

    // 1. 本地离线瓦片（原生支持到18级，深度缩放到21级自动超分平滑放大）
    const localTiles = L.tileLayer('../../assets/tiles/{{z}}_{{x}}_{{y}}.png', {{
      minZoom: 14,
      maxNativeZoom: 18,
      maxZoom: 21,
      bounds: campusBounds,
      attribution: '本地离线瓦片 (assets/tiles)'
    }}).addTo(map);

    // 2. Esri 高清卫星遥感图层（原生19级，可平滑缩放到21级超近距离细节）
    const esriSatellite = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{{z}}/{{y}}/{{x}}', {{
      attribution: 'Tiles &copy; Esri World Imagery',
      minZoom: 14,
      maxNativeZoom: 19,
      maxZoom: 21
    }});

    const baseMaps = {{
      "🛰️ Esri 高清遥感卫星图 (深度放大描摹)": esriSatellite,
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

    // 绘图状态
    let isDrawing = false;
    let drawType = null; // 'polygon' | 'road' | 'circle'
    let drawingPoints = [];
    let drawingMarkers = [];
    let drawingLine = null;
    let circleCenter = null;
    let circlePreview = null;

    let buildingsLayer = null;
    let roadsLayer = null;
    let poisLayer = null;

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

    // ==========================================
    // ✏️ 交互式绘图功能
    // ==========================================
    window.startDrawPolygon = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'polygon';
      drawingPoints = [];
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '📍 <b>正在绘制多边形建筑</b>：请在卫星底图上依次点击建筑物拐角点，点击完毕后点击【完成绘制并填信息】。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    window.startDrawCircle = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'circle';
      circleCenter = null;
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '⭕ <b>正在绘制圆形建筑</b>：第 1 次点击：确定圆心；移动鼠标可预览大小；第 2 次点击：确定半径边缘。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    window.startDrawRoad = function() {{
      cancelVertexEditing();
      isDrawing = true;
      drawType = 'road';
      drawingPoints = [];
      clearDrawingVisuals();
      document.getElementById('drawControlRow').style.display = 'flex';
      document.getElementById('statusHint').innerHTML = '🚶 <b>正在绘制步道</b>：请沿着道路走向依次点击打点，点击完毕后点击【完成绘制并填信息】。';
      map.getContainer().style.cursor = 'crosshair';
    }};

    map.on('click', function(e) {{
      if (!isDrawing) return;
      const lat = e.latlng.lat;
      const lng = e.latlng.lng;

      if (drawType === 'circle') {{
        if (!circleCenter) {{
          // 第 1 步：定圆心
          circleCenter = e.latlng;
          const cm = L.circleMarker([lat, lng], {{ radius: 5, color: '#9333ea', fillColor: '#fff', fillOpacity: 1 }}).addTo(map);
          drawingMarkers.push(cm);
          document.getElementById('statusHint').innerHTML = '⭕ <b>圆心已定</b>：请移动鼠标观察大小，并在圆周边缘再次点击确定。';
        }} else {{
          // 第 2 步：定半径，生成平滑24边形
          const radiusMeters = circleCenter.distanceTo(e.latlng);
          const circlePolyCoords = generateCirclePolygon(circleCenter, radiusMeters, 24);
          openNewModalForDrawnPolygon(circlePolyCoords);
        }}
        return;
      }}

      // 多边形或线
      drawingPoints.push([lng, lat]);
      const m = L.circleMarker([lat, lng], {{ radius: 4, color: '#ef4444', fillColor: '#fff', fillOpacity: 1 }}).addTo(map);
      drawingMarkers.push(m);
      updateDrawingVisuals();
    }});

    map.on('mousemove', function(e) {{
      if (!isDrawing || drawType !== 'circle' || !circleCenter) return;
      const radiusMeters = circleCenter.distanceTo(e.latlng);
      if (circlePreview) map.removeLayer(circlePreview);
      circlePreview = L.circle(circleCenter, {{
        radius: radiusMeters,
        color: '#9333ea',
        weight: 2,
        fillColor: '#c084fc',
        fillOpacity: 0.35,
        dashArray: '4, 4'
      }}).addTo(map);
    }});

    // 生成正多边形逼近圆形的标准算法（24边形）
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
      coords.push(coords[0]); // 闭合
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
      document.getElementById('statusHint').innerHTML = '💡 <b>编辑模式已就绪</b>：点击地图上的建筑即可修改，或点击上方按钮新增。';
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
        renderAllLayers();
        alert('✅ 新步道已添加！');
      }}
    }};

    // ==========================================
    // 🏷️ 属性弹窗
    // ==========================================
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
      renderAllLayers();
      alert('✅ 建筑文本与属性已更新！');
    }};

    window.deleteCurrentFeature = function() {{
      if (!confirm('确定要删除这栋建筑吗？')) return;
      if (editingFeature) {{
        const idx = buildingsData.features.indexOf(editingFeature);
        if (idx >= 0) buildingsData.features.splice(idx, 1);
      }}
      closeModal();
      cancelVertexEditing();
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
        }}
        activeVertexMarkers.push(marker);
      }});
    }}

    function cancelVertexEditing() {{
      activeVertexMarkers.forEach(m => map.removeLayer(m));
      activeVertexMarkers = [];
    }}

    window.saveAllChanges = function() {{
      const payload = {{
        buildings: buildingsData,
        roads: roadsData,
        pois: poisData
      }};

      fetch('/api/save', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify(payload)
      }})
      .then(res => res.json())
      .then(data => {{
        if (data.status === 'ok') {{
          alert('保存成功！\\n修改已直接自动写回本地 tools/map/ 对应的 GeoJSON 文件！');
        }} else {{
          throw new Error(data.message);
        }}
      }})
      .catch(err => {{
        console.warn('本地微服务未开启，回退为浏览器文件下载模式', err);
        exportGeoJsonBackup();
        alert('本地服务器未响应，已自动触发 GeoJSON 文件下载！');
      }});
    }};

    window.exportGeoJsonBackup = function() {{
      const blob = new Blob([JSON.stringify(buildingsData, null, 2)], {{ type: 'application/json' }});
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'usst_516_buildings.geojson';
      a.click();
    }};
  </script>
</body>
</html>
"""

with open('tools/map/viewer.html', 'w', encoding='utf-8') as f:
    f.write(html)

print("Updated viewer.html with Zoom 21 support and Circle Tool!")
