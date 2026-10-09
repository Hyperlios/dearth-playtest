extends "res://mobile/baseline_ui.gd"
## Browser-only adaptation of the original 2026-10-05 playtest UI.
## Original game rules, progression, economy and saves remain in the original PCK.
var mobile_mode := true
var mobile_top: Panel
var mobile_dock: Panel
var mobile_stats: Label
var mobile_round: Label
var mobile_tabs := {}
var drawer := ""
var close_drawer: Button
var mobile_start: Button
var mobile_speed: Button
var mobile_pause: Button
var mobile_zoom: Button
var mobile_return:Button
var mobile_selection_key := ""
var mobile_size := Vector2.ZERO
var phone_font_tick := 0.0
var modal_scrolls := {}
var mobile_qa := false

func setup(p_main) -> void:
	main = p_main
	mobile_mode = "--mobile-ui" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		mobile_mode = bool(JavaScriptBridge.eval('matchMedia("(pointer:coarse)").matches || location.search.includes("phone=1")'))
	_build_ori_matrix()
	FONT = load("res://assets/fonts/NotoSansSC-Regular.ttf")
	var weight := FontVariation.new()
	weight.base_font = FONT
	weight.variation_embolden = 0.5
	font_bold = weight
	title_font = weight
	icon_grade = ShaderMaterial.new()
	icon_grade.shader = preload("res://assets/ui_icon_grade.gdshader")
	for i in 3:
		icon_grade.set_shader_parameter("row%d" % i,Vector3(_ori_m[i*3],_ori_m[i*3+1],_ori_m[i*3+2]))

	root = Control.new()
	root.name = "ui_root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	board_drop = preload("res://scenes/garden_drop_board.gd").new()
	board_drop.ui = self
	board_drop.name = "GardenBoardDrop"
	board_drop.mouse_filter = Control.MOUSE_FILTER_PASS
	board_drop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(board_drop)

	# Atmosphere behind interface: cards and labels retain their intended contrast.
	_build_vignette()
	_build_market()
	_build_battle_tray()
	_build_progress()
	_build_header()
	_build_round_ribbon()
	_build_board_foot()
	_build_view_controls()
	_build_left_rail()
	_build_aside()
	_build_greenhouse_entry()
	_build_toast()
	_build_gh()
	_build_modal_layer()
	for panel in [money_card,supply_summary,market,gh_panel]:
		add_forest_trim(panel)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_relayout):
		vp.size_changed.connect(_relayout)
	# setup() 是在 add_child(ui) **之前**被调用的，此刻本节点还没进树，
	# get_tree() / get_viewport() 都是 null。真正的首帧布局放到 tree_entered。
	if not tree_entered.is_connected(_on_tree_entered):
		tree_entered.connect(_on_tree_entered)
	_build_mobile()
	_relayout()


func _build_mobile() -> void:
	mobile_mode = '--mobile-ui' in OS.get_cmdline_user_args()
	if OS.has_feature('web'):
		mobile_mode = bool(JavaScriptBridge.eval('matchMedia("(pointer:coarse)").matches || location.search.includes("phone=1")'))
	if OS.has_feature('web'):mobile_qa=bool(JavaScriptBridge.eval('location.search.includes("qa=1")'))
	root.theme=Theme.new()
	root.theme.default_font=FONT
	root.theme.default_font_size=14
	if not mobile_mode:return
	mobile_top=Panel.new(); root.add_child(mobile_top)
	mobile_top.add_theme_stylebox_override('panel',_sb(Color('#10281feb'),8,Color('#8f9b6c'),1))
	mobile_stats=_label(mobile_top,'',16,Color('#efdfaf'),true)
	mobile_round=_label(mobile_top,'',13,Color('#c5d6b7'))
	var menu=_button(mobile_top,'菜单',_show_menu);menu.name='PhoneMenu'
	var zoom=_button(mobile_top,'视角',_toggle_zoom);zoom.name='PhoneZoom'
	mobile_dock=Panel.new();root.add_child(mobile_dock)
	mobile_dock.add_theme_stylebox_override('panel',_sb(Color('#10281ff5'),8,Color('#6c8267'),1))
	for pair in [['shop','商店'],['seeds','种子'],['army','军团'],['greenhouse','温室'],['selection','详情']]:
		var key:String=pair[0]
		mobile_tabs[key]=_button(mobile_dock,pair[1],func():_set_drawer(key))
	mobile_start=_button(mobile_dock,'开始守夜',func():drawer='';main.try_start())
	mobile_start.add_theme_stylebox_override('normal',_sb(Color('#c8d09d'),7,Color('#efddb0'),1))
	mobile_start.add_theme_color_override('font_color',Color('#193529'))
	mobile_speed=_button(mobile_dock,'1 倍速',func():main.speed=2.0 if main.speed==1.0 else (3.0 if main.speed==2.0 else 1.0))
	mobile_pause=_button(mobile_dock,'暂停',func():main.paused=not main.paused)
	mobile_zoom=_button(mobile_dock,'视角',_toggle_zoom)
	mobile_tabs['damage']=_button(mobile_dock,'战报',func():_set_drawer('damage'))
	close_drawer=_button(root,'收起',func():_set_drawer(''))
	close_drawer.name='PhoneCloseDrawer'
	mobile_return=_button(root,'显示界面',func():set_immersive(false))
	# The start control belongs in the thumb bar, not a second right-hand column.
	ledger.hide()

func _set_drawer(value:String) -> void:
	drawer='' if drawer==value else value
	close_seed_wheel()
	gh_panel.visible=drawer=='greenhouse'
	if g!=null and gh_panel.visible:_refresh_gh()
	_relayout()
	if main!=null:main._update_camera()

func _relayout() -> void:
	if not mobile_mode or mobile_top==null:
		super._relayout()
		return
	var vp=_vp();var w=vp.x;var h=vp.y
	mobile_size=vp
	_rect(root,0,0,w,h)
	_rect(board_drop,0,0,w,h)
	for node in [header,round_ribbon,board_foot,view_controls,gh_entry,progress_track,vignette]:node.hide()
	_rect(mobile_top,6,4,w-12,48)
	_rect(mobile_stats,10,3,w-178,22)
	_rect(mobile_round,10,26,w-150,18)
	_rect(mobile_top.get_node('PhoneMenu'),w-90,2,70,44)
	_rect(mobile_top.get_node('PhoneZoom'),w-166,2,70,44)
	_rect(mobile_dock,6,h-52,w-12,48)
	var battle=_is_battle()
	for k in mobile_tabs:mobile_tabs[k].visible=(k=='damage') if battle else (k!='damage')
	mobile_start.visible=not battle
	mobile_speed.visible=battle;mobile_pause.visible=battle;mobile_zoom.visible=battle
	var x=4.0
	if battle:
		for b in [mobile_speed,mobile_pause,mobile_zoom,mobile_tabs.damage]:
			_rect(b,x,2,80,44);x+=86
	else:
		var tab_w=clampf((w-174)/5.0,48,90)
		for key in ['shop','seeds','army','greenhouse','selection']:
			_rect(mobile_tabs[key],x,2,tab_w,44);x+=tab_w+4
		_rect(mobile_start,w-144,2,126,44)
	var dh=minf(174,h-116)
	market.visible=not battle and drawer in ['shop','seeds']
	seed_tray.visible=drawer=='seeds';shop_floor.visible=drawer=='shop'
	var mh=dh if drawer=='shop' else 90.0
	_rect(market,6,h-58-mh,w-12,mh)
	_rect(seed_tray,6,4,w-28,80)
	seed_label.hide()
	_rect(inv_scroll,8,16,w-58,56)
	_rect(shop_floor,8,8,w-28,dh-16)
	# Horizontal tool buttons; cards below them retain a fixed, readable width.
	_rect(shop_tools,0,0,0,0);shop_tools.hide()
	for b in [btn_upgrade,btn_refresh,btn_lock]:
		if b.get_parent()!=shop_floor:b.reparent(shop_floor)
		b.show();b.custom_minimum_size=Vector2.ZERO
	_rect(btn_upgrade,0,0,160,44);_rect(btn_refresh,166,0,110,44);_rect(btn_lock,282,0,110,44)
	odds_label.hide()
	_rect(shop_row,0,50,w-28,dh-64)
	shop_row.columns=5
	shop_row.add_theme_constant_override('h_separation',6)
	aside.visible=not battle and drawer=='selection'
	_rect(aside,w-minf(w*.46,320)-6,60,minf(w*.46,320),h-120)
	ledger.hide()
	selection.visible=true
	_rect(selection,0,0,aside.size.x,aside.size.y)
	_rect(selection_scroll,12,10,aside.size.x-24,aside.size.y-20)
	selection_box.custom_minimum_size.x=0
	left_rail.visible=drawer=='army'
	_rect(left_rail,6,60,200,h-120)
	_rect(rail_pill,10,6,180,22)
	_rect(army_scroll,8,30,184,left_rail.size.y-60)
	army_box.custom_minimum_size.x=170
	_rect(relics_label,10,left_rail.size.y-27,180,22)
	gh_panel.visible=not battle and drawer=='greenhouse'
	if gh_panel.visible:_place_gh_panel()
	battle_tray.visible=battle and drawer=='damage'
	_rect(battle_tray,6,h-160,w-12,102)
	_rect(damage_board,10,10,w-34,82)
	damage_board.columns=2
	close_drawer.visible=drawer!=''
	var cx=w-84.0;var cy=h-58-mh-46
	if drawer in ['selection','greenhouse']:cx=w-minf(w*.46,320)-90;cy=60
	if drawer=='army':cx=212;cy=60
	if drawer=='damage':cy=h-206
	_rect(close_drawer,cx,maxf(56,cy),78,44)
	_rect(toast,w*.5-160,58,320,44)
	if aside.visible:_fit_selection.call_deferred()
	mobile_return.visible=immersive
	_rect(mobile_return,w-116,h-52,110,44)
	if immersive:
		for item in [mobile_top,mobile_dock,market,aside,left_rail,gh_panel,battle_tray,close_drawer]:item.hide()
	else:
		mobile_top.show();mobile_dock.show()
	if modal_layer!=null:
		_rect(modal_layer,0,0,w,h)
		for c in modal_layer.get_children():
			if c is Panel and c.has_meta('v'):_recenter_modal.call_deferred(c)

func safe_insets() -> Dictionary:
	if not mobile_mode:return super.safe_insets()
	if immersive:return {'top':0.0,'bottom':0.0,'left':0.0,'right':0.0}
	return {'top':56.0,'bottom':58.0,'left':8.0,'right':8.0}

func _process(delta:float) -> void:
	super._process(delta)
	if not mobile_mode:return
	if OS.has_feature('web'):
		var size_data=JavaScriptBridge.eval('window.dearthViewportSize ? window.dearthViewportSize() : null')
		if size_data!=null:
			var values=JSON.parse_string(str(size_data))
			if values is Array and values.size()==2:
				var desired=Vector2i(int(values[0]),int(values[1]))
				if desired.x>0 and desired.y>0 and get_tree().root.content_scale_size!=desired:
					get_tree().root.content_scale_size=desired
	if mobile_size!=_vp():_relayout()
	var available_h=maxf(180,_vp().y-(0 if immersive else 114))
	var base_zoom=available_h/780.0*1.3
	var fit_width=(_vp().x-16)/1200.0/base_zoom
	var desired_zoom=1.0/1.3 if main.zoom_out else maxf(1.0,fit_width)
	if not is_equal_approx(main.zoom_scale,desired_zoom):
		main.zoom_scale=desired_zoom
		main._update_camera()
	if g==null:
		if mobile_qa:_publish_qa()
		return
	if (main.transfer!=null or main.deploy_arm>=0) and drawer in ['greenhouse','selection']:_set_drawer('')
	phone_font_tick+=delta
	mobile_speed.text='%d 倍速' % int(main.speed)
	mobile_pause.text='继续' if main.paused else '暂停'
	if phone_font_tick>.2:
		phone_font_tick=0
		_fix_text(root)
		_fix_text(modal_layer)
		if mobile_qa:_publish_qa()

func sync() -> void:
	super.sync()
	if not mobile_mode or mobile_top==null or g==null:return
	var eco:Dictionary=g.payment if _is_battle() and g.payment!=null else g.economy()
	mobile_stats.text='金币 %d    产粮 %d  −  口粮 %d  =  余粮 %d' % [g.gold,eco.available,eco.need,eco.left]
	var fee:int=g.greenhouseBill()
	mobile_round.text='第 %d / 40 夜  ·  商店 %d 级  ·  售粮 +%d 金%s' % [g.get_round(),g.level(),eco.income,('  ·  温室 %d 金/夜' % fee) if fee>0 else '']
	mobile_stats.add_theme_color_override('font_color',Color('#efab92') if int(eco.left)<0 else Color('#efdfaf'))
	mobile_start.text='开始守夜' if int(eco.left)>=0 and g.gold>=fee else '检查供养'
	mobile_start.disabled=g.phase!='prep'
	var key=str(main.selection)
	if key!=mobile_selection_key:
		mobile_selection_key=key
		if main.selection.kind!='none' and drawer not in ['seeds','greenhouse'] and not _is_battle():drawer='selection'
	if _is_battle() and drawer!='damage':drawer=''
	if not _is_battle() and drawer=='damage':drawer=''
	_relayout()

func _fit_selection() -> void:
	if not mobile_mode:super._fit_selection()
	elif aside!=null and selection!=null:
		var fit=minf(aside.size.y,maxf(100,selection_box.get_combined_minimum_size().y+24))
		_rect(selection,0,0,aside.size.x,fit)
		_rect(selection_scroll,12,10,aside.size.x-24,fit-20)

func _clean_text(value:String) -> String:
	var replacements={'⛶':'全屏','♫':'音乐','⌑':'锁','☰':'菜单','⌂':'温室','↻':'刷新','▶':'开始','Ⅱ':'暂停'}
	for key in replacements:value=value.replace(key,replacements[key])
	return value

func _fix_text(node:Node) -> void:
	if node is Label:
		node.add_theme_font_override('font',FONT)
		node.text=_clean_text(node.text)
	elif node is Button:
		node.add_theme_font_override('font',font_bold)
		node.text=_clean_text(node.text)
		if node.is_visible_in_tree():node.custom_minimum_size.y=maxf(node.custom_minimum_size.y,44)
	for c in node.get_children():_fix_text(c)

func _label(parent:Control,text:String,size:int,col:Color,bold:=false,letter:=0)->Label:
	var l:Label=super._label(parent,_clean_text(text),maxi(13,mini(size,28)) if mobile_mode else size,col,bold,0 if mobile_mode else letter)
	return l

func _button(parent:Control,text:String,on_press:Callable)->Button:
	var b:Button=super._button(parent,_clean_text(text),on_press)
	if mobile_mode:
		b.custom_minimum_size=Vector2(72,44)
		b.add_theme_font_size_override('font_size',14)
	return b

func _shop_card(i:int,s:Dictionary)->Button:
	if not mobile_mode:return super._shop_card(i,s)
	var d:Dictionary=Data.CARDS[s.id]
	var b=Button.new()
	b.custom_minimum_size=Vector2(0,94)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.clip_contents=true
	b.add_theme_stylebox_override('normal',_sb(Color('#254235'),6,_tier_color(int(d.cost)),1))
	b.add_theme_stylebox_override('hover',_sb(Color('#3c5940'),6,Color('#ddc98f'),1))
	b.add_theme_stylebox_override('pressed',_sb(Color('#183329'),6,Color('#ddc98f'),1))
	if bool(s.sold):b.modulate.a=0;b.mouse_filter=Control.MOUSE_FILTER_IGNORE;return b
	var price:int=g.seedPrice(s.id)
	b.disabled=g.gold<price;b.modulate.a=.45 if b.disabled else 1.0
	var icon=TextureRect.new();icon.texture=_icon(s.id,1)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);icon.offset_left=8;icon.offset_right=-8;icon.offset_bottom=46
	var nm=_label(b,str(d.name),14,Color('#efdfbb'),true)
	nm.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);nm.offset_top=46;nm.offset_bottom=68;nm.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var price_label=_label(b,'%d 金 · %s' % [price,'粮食' if d.kind=='food' else '战斗'],13,Color('#dfc88b'))
	price_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);price_label.offset_top=69;price_label.offset_bottom=91;price_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func():main.buy_and_select(i))
	return b

func _sync_market(prep:bool)->void:
	super._sync_market(prep)
	if not mobile_mode or not prep:return
	btn_refresh.text='刷新 · 2 金'
	btn_upgrade.text='升 %d 级 · %d 金' % [g.level()+1,g.shopUpgradeCost()] if g.level()<8 else '已满级'
	btn_lock.text='已锁定' if g.locked else '锁定一轮'
	for b in [btn_refresh,btn_upgrade,btn_lock]:b.add_theme_font_size_override('font_size',14)
	for c in inv_row.get_children():
		if c is Button:
			c.custom_minimum_size.y=52
			c.custom_minimum_size.x=maxf(c.custom_minimum_size.x,126)
			for n in c.get_children():
				if n is Label:_rect(n,38,0,c.custom_minimum_size.x-40,52)
				elif n is TextureRect:_rect(n,4,8,32,36)

func _place_gh_panel()->void:
	if not mobile_mode:super._place_gh_panel();return
	var vp=_vp();var w=minf(vp.x*.46,320)
	var fit=minf(vp.y-120,maxf(160,gh_box.get_combined_minimum_size().y+24))
	_rect(gh_panel,vp.x-w-6,60,w,fit)
	_rect(gh_scroll,12,10,w-24,gh_panel.size.y-20)

func toggle_greenhouse()->void:
	if not mobile_mode:super.toggle_greenhouse();return
	_set_drawer('greenhouse')

func _refresh_gh()->void:
	super._refresh_gh()
	if not mobile_mode or not gh_panel.visible:return
	_place_gh_panel.call_deferred()
	for c in gh_box.get_children():
		if c is Button and c.get('slot')!=null and int(c.slot)>=0:
			var slot:int=c.slot
			if slot<g.greenhouse.slots.size() and g.greenhouse.slots[slot]==null:
				if not c.has_meta('tap_seed'):
					c.set_meta('tap_seed',true)
					c.pressed.connect(func():_choose_seed(-1,slot))
				if c.has_meta('empty_label'):c.get_meta('empty_label').text='点击选择种子'

func open_seed_wheel(pid:int,page:int=0)->void:
	if not mobile_mode:super.open_seed_wheel(pid,page);return
	_choose_seed(pid,-1)

func _choose_seed(pid:int,slot:int)->void:
	if g==null or g.phase!='prep':return
	var panel=_open_modal(minf(_vp().x-24,580))
	var v=_modal_body(panel)
	_label(v,'播种到温室' if slot>=0 else '选择种子',22,Color('#efdfbb'),true)
	if g.inventory.is_empty():_label(v,'种子袋空了，请先到商店购买。',15,Color('#b8cbb3'))
	for i in g.inventory.size():
		var id:String=g.inventory[i];var d:Dictionary=Data.CARDS[id];var index:int=i
		_button(v,'%s  ·  %s' % [d.name,'持续产粮' if d.kind=='food' else '战斗作物'],func():
			var ok:bool=g.plantGreenhouse(index,slot) if slot>=0 else g.plant(index,pid)
			if ok:
				close_modal();drawer='';main.seed_index=-1
				main._save_checkpoint();sync();notify('已播种')
				if pid>=0:_garden_pulse(pid))
	_button(v,'返回',close_modal)
	_recenter_modal.call_deferred(panel)

func _recenter_modal(panel:Panel)->void:
	if not mobile_mode:super._recenter_modal(panel);return
	if not is_instance_valid(panel) or not panel.has_meta('v') or not modal_layer.visible:return
	var v:VBoxContainer=panel.get_meta('v')
	var vp=_vp()
	if not panel.has_meta('mobile_width'):panel.set_meta('mobile_width',panel.custom_minimum_size.x)
	var w=minf(maxf(400,float(panel.get_meta('mobile_width'))),vp.x-24)
	panel.custom_minimum_size=Vector2.ZERO
	var scroll:ScrollContainer
	if panel.has_meta('mobile_scroll'):scroll=panel.get_meta('mobile_scroll')
	else:
		scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
		panel.add_child(scroll);v.reparent(scroll);panel.set_meta('mobile_scroll',scroll)
		v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override('separation',8)
	_fix_text(v)
	var need=v.get_combined_minimum_size()
	var h=minf(need.y+28,vp.y-24)
	_rect(panel,(vp.x-w)*.5,(vp.y-h)*.5,w,h)
	_rect(scroll,14,14,w-28,h-28)
	v.custom_minimum_size.x=w-44

func show_title(has_save:bool)->void:
	if not mobile_mode:super.show_title(has_save);return
	main._music_play('title');root.hide();main.paused=true
	var p=_open_modal(460);var v=_modal_body(p)
	_center(_label(v,'荒年',36,Color('#efdfbb'),true))
	_center(_label(v,'种下希望，守过四十夜',14,Color('#bacfb5')))
	if has_save:_button(v,'继续旅程',func():main.load_save())
	_button(v,'新旅程',func():show_difficulty(1))
	var row=HBoxContainer.new();v.add_child(row)
	for pair in [['设置',show_settings],['图鉴',show_collection],['玩法',func():show_tutorial(0)]]:
		var b=_button(row,pair[0],pair[1]);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_recenter_modal.call_deferred(p)

func show_difficulty(chosen:=1)->void:
	if not mobile_mode:super.show_difficulty(chosen);return
	main.paused=true
	var p=_open_modal(590);var v=_modal_body(p)
	_label(v,'选择难度',23,Color('#efdfbb'),true)
	_label(v,'通关 40 夜，解锁下一难度。',14,Color('#bacfb5'))
	var row=HBoxContainer.new();v.add_child(row)
	for d in range(1,6):
		var b=_button(row,'%d · %s' % [d,Data.DIFFICULTIES[d].name] if d<=main.progress.unlocked else '%d · 锁定' % d,func():show_difficulty(d))
		b.disabled=d>main.progress.unlocked;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(v,'当前：难度 %d · %s' % [chosen,Data.DIFFICULTIES[chosen].name],18,Color('#e6d39e'),true)
	_button(v,'开始旅程',func():
		if chosen>main.progress.unlocked:return
		main.new_game(chosen)
		if not main.progress.tutorial:show_tutorial(0))
	_button(v,'返回',func():show_title(FileAccess.file_exists(main.SAVE_PATH)))
	_recenter_modal.call_deferred(p)

func show_report()->void:
	if not mobile_mode:super.show_report();return
	var p=_open_modal(500);var v=_modal_body(p);var r:Dictionary=g.report
	_label(v,'第 %d 夜 · 平安归来' % int(r.round),24,Color('#efdfbb'),true)
	_label(v,'售粮 +%d 金    击退 %d 只    温室 -%d 金' % [r.payment.income,r.kills,r.payment.get('greenhouseFee',0)],16,Color('#cfdaad'))
	_label(v,'作物损失 %d  ·  土地损失 %d  ·  归队 %d' % [r.eaten,r.landLost,r.down],14,Color('#b5cbb1'))
	_button(v,'迎接第 %d 个白昼' % (int(r.round)+1),func():drawer='';main.report_continue())
	_recenter_modal.call_deferred(p)

func show_draft()->void:
	if not mobile_mode:super.show_draft();return
	var p=_open_modal(610);var v=_modal_body(p)
	_label(v,'森林的馈赠 · 选择一项',22,Color('#efdfbb'),true)
	for relic in g.offer:
		var id:String=relic.id
		var b=_button(v,str(relic.name)+'\n'+str(relic.desc),func():main.draft_choose(id))
		b.custom_minimum_size.y=74;b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_recenter_modal.call_deferred(p)

func show_tutorial(step:int)->void:
	if not mobile_mode:super.show_tutorial(step);return
	if not tutorial_active:
		tutorial_was_paused=main.paused
		tutorial_active=true
	main.paused=true
	var p=_open_modal(590);var v=_modal_body(p)
	_label(v,'农庄入门  %d / %d' % [step+1,LESSONS.size()],14,Color('#b5cbb1'))
	_label(v,LESSONS[step][0],22,Color('#efdfbb'),true)
	var text:String=LESSONS[step][1]
	if step==0:text='小屋在中央，饥饿从四面而来。守住它，迎接 40 次日出。手指拖动空地，可以查看周边。'
	if step==1:text='点底部商店购买种子，再点一块空田，从列表里选种子即可播种。种子袋里的种子也能拖入田地。'
	var desc=_label(v,text,16,Color('#d4dfbd'))
	desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size=Vector2(0,76)
	var row=HBoxContainer.new();row.add_theme_constant_override('separation',8);v.add_child(row)
	_button(row,'跳过',finish_tutorial).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if step>0:_button(row,'上一步',func():show_tutorial(step-1)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(row,'开始经营' if step==LESSONS.size()-1 else '下一步',func():
		if step==LESSONS.size()-1:finish_tutorial()
		else:show_tutorial(step+1)).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_recenter_modal.call_deferred(p)

func _publish_qa()->void:
	var buttons:Array=[]
	var missing:Array=[]
	_scan_qa(self,buttons,missing)
	var plots:Array=[]
	if g!=null:
		for p in g.plots_arr:
			if p.owned:
				var at:Vector2=main.world.get_global_transform_with_canvas()*Vector2(p.x,p.y)
				plots.append({'id':p.id,'x':at.x,'y':at.y,'empty':p.crop==null})
	var data={'size':[_vp().x,_vp().y],'drawer':drawer,'phase':g.phase if g!=null else 'title','buttons':buttons,'missing':missing,'plots':plots}
	JavaScriptBridge.eval('window.dearthQA='+JSON.stringify(data))

func _scan_qa(node:Node,buttons:Array,missing:Array)->void:
	if node is Control and not node.is_visible_in_tree():return
	if node is Button:
		var r:Rect2=node.get_global_rect()
		buttons.append({'text':node.text,'x':r.position.x+r.size.x/2,'y':r.position.y+r.size.y/2,'width':r.size.x,'height':r.size.y,'disabled':node.disabled})
	if node is Label or node is Button:
		var text:String=node.text
		for ch in text:
			if ch!='\n' and ch!='\t' and not FONT.has_char(ch.unicode_at(0)) and not missing.has(ch):missing.append(ch)
	for c in node.get_children():_scan_qa(c,buttons,missing)

func _unit_button(u:Dictionary)->Button:
	if not mobile_mode:return super._unit_button(u)
	var b=Button.new()
	b.custom_minimum_size=Vector2(172,68)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override('normal',_sb(Color('#294535'),6,Color('#8fa17a'),1))
	b.add_theme_stylebox_override('hover',_sb(Color('#3b5840'),6,Color('#dccb91'),1))
	var art=TextureRect.new();art.texture=_icon(u.card,int(u.star))
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(art);_rect(art,2,6,46,54)
	_rect(_label(b,str(Data.CARDS[u.card].name),14,Color('#efdfbb'),true),50,4,124,22)
	_rect(_label(b,'%d 星 · %d 粮/夜' % [u.star,g.unitUpkeep(u)],13,Color('#c2d0ac')),50,30,124,22)
	var uid:int=u.id
	b.pressed.connect(func():_select_unit(uid))
	return b

func _damage_entry(u:Dictionary,mx:float)->Control:
	if not mobile_mode:return super._damage_entry(u,mx)
	var v=VBoxContainer.new()
	v.custom_minimum_size=Vector2(0,36);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(v,'%s   %d' % [Data.CARDS[u.card].name,int(u.get('damageDone',0))],14,Color('#e4d7ac'))
	var bar=ProgressBar.new();bar.show_percentage=false
	bar.custom_minimum_size.y=4;bar.max_value=mx;bar.value=float(u.get('damageDone',0))
	bar.add_theme_stylebox_override('background',_sb(Color('#102a23'),2))
	bar.add_theme_stylebox_override('fill',_sb(Color('#b9c492'),2));v.add_child(bar)
	return v

func _show_menu()->void:
	if not mobile_mode:super._show_menu();return
	var p=_open_modal(500);var v=_modal_body(p)
	_label(v,'农庄菜单',22,Color('#efdfbb'),true)
	var grid=GridContainer.new();grid.columns=2
	grid.add_theme_constant_override('h_separation',8);grid.add_theme_constant_override('v_separation',8);v.add_child(grid)
	var items=[['设置',show_settings],['植物图鉴',show_collection],['玩法说明',func():show_tutorial(0)],['保存进度',func():close_modal();main.manual_save()],['返回标题',func():close_modal();main.to_title()],['新旅程',func():show_difficulty(1)]]
	for pair in items:_button(grid,pair[0],pair[1]).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(v,'返回农庄',close_modal)
	_recenter_modal.call_deferred(p)
