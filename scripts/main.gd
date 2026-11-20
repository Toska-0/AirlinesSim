extends Control

const BG := Color("#0b1720")
const PANEL := Color("#142733")
const PANEL_ALT := Color("#1b3441")
const ACCENT := Color("#62d6bd")
const TEXT := Color("#edf5f4")
const MUTED := Color("#91a9ad")

var page := "Обзор"
var root_box: VBoxContainer
var content: VBoxContainer
var header: HBoxContainer
var status_label: Label

func _ready() -> void:
	_build_shell()
	if GameData.load_game():
		_refresh()
	else:
		_show_company_setup()

func _process(delta: float) -> void:
	GameData.advance_simulation(delta)
	if GameData.has_game():
		_refresh_header()

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	root_box = VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 10)
	root_box.add_theme_color_override("font_color", TEXT)
	root_box.add_theme_constant_override("margin_left", 16)
	root_box.add_theme_constant_override("margin_right", 16)
	root_box.add_theme_constant_override("margin_top", 16)
	root_box.add_theme_constant_override("margin_bottom", 12)
	add_child(root_box)
	header = HBoxContainer.new()
	root_box.add_child(header)
	var brand := Label.new()
	brand.text = "✈ AIRLINES SIM"
	brand.add_theme_font_size_override("font_size", 21)
	brand.add_theme_color_override("font_color", ACCENT)
	header.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	status_label = Label.new()
	status_label.text = "НОВАЯ ИГРА"
	status_label.add_theme_color_override("font_color", MUTED)
	header.add_child(status_label)
	var line := HSeparator.new()
	root_box.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var nav := GridContainer.new()
	nav.columns = 4
	nav.add_theme_constant_override("h_separation", 6)
	nav.add_theme_constant_override("v_separation", 6)
	root_box.add_child(nav)
	for name in ["Обзор", "Карта", "Флот", "Маршруты", "Аэропорты", "Финансы", "События", "Сохранения"]:
		var button := Button.new()
		button.text = name
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_navigate.bind(name))
		_style_button(button, name == page)
		nav.add_child(button)

func _navigate(target: String) -> void:
	page = target
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(content):
		return
	for child in content.get_children():
		child.queue_free()
	if not GameData.has_game():
		_show_company_setup()
		return
	match page:
		"Обзор": _page_dashboard()
		"Карта": _page_map()
		"Флот": _page_fleet()
		"Маршруты": _page_routes()
		"Аэропорты": _page_airports()
		"Финансы": _page_finance()
		"События": _page_events()
		"Сохранения": _page_saves()
	_refresh_header()

func _refresh_header() -> void:
	if not GameData.has_game():
		return
	var c: Dictionary = GameData.state.company
	status_label.text = "%s  •  DAY %d  •  %02d:%02d" % [c.name, GameData.state.day, int(GameData.state.minute) / 60, int(GameData.state.minute) % 60]

func _page_dashboard() -> void:
	var c: Dictionary = GameData.state.company
	_section("КОМПАНИЯ", c.name + "  /  " + c.code)
	_metric_grid([
		["ДЕНЬГИ", GameData.format_money(GameData.state.money)],
		["САМОЛЁТЫ", str(GameData.state.aircraft.size())],
		["МАРШРУТЫ", str(GameData.state.routes.size())],
		["РЕПУТАЦИЯ", str(roundi(c.reputation)) + "/100"]
	])
	_section("УПРАВЛЕНИЕ ВРЕМЕНЕМ", "Симуляция продолжается, пока игра открыта")
	var speed_row := HBoxContainer.new()
	content.add_child(speed_row)
	for pair in [["Ⅱ",0.0],["1×",1.0],["2×",2.0],["4×",4.0],["8×",8.0]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): GameData.paused = pair[1] == 0.0; GameData.sim_speed = maxf(1.0, pair[1]); _refresh())
		_style_button(b, (GameData.paused and pair[1] == 0.0) or (not GameData.paused and GameData.sim_speed == pair[1]))
		speed_row.add_child(b)
	_section("ПОСЛЕДНИЕ ОПЕРАЦИИ", "Финансовый журнал")
	if GameData.state.ledger.is_empty():
		_note("Пока нет операций. Купите самолёт и откройте первый маршрут.")
	else:
		for item in GameData.state.ledger.slice(0, 5):
			_row(item.label, ("+" if item.amount >= 0 else "") + GameData.format_money(item.amount), item.amount >= 0)
	_section("БЫСТРЫЙ СТАРТ", "Первые шаги вашей авиакомпании")
	_action("Открыть каталог самолётов", func(): _navigate("Флот"))
	_action("Создать первый маршрут", func(): _navigate("Маршруты"))

func _page_map() -> void:
	_section("СЕТЬ МАРШРУТОВ", "Схематичная офлайн-карта аэропортов • координаты WGS84")
	var map_panel := PanelContainer.new()
	_style_panel(map_panel)
	content.add_child(map_panel)
	var map := Control.new()
	map.custom_minimum_size = Vector2(0, 250)
	map.draw.connect(func():
		var rect := map.get_rect()
		for i in range(1, 7):
			var y := rect.size.y * float(i) / 7.0
			map.draw_line(Vector2(8,y), Vector2(rect.size.x-8,y), Color("#294653"), 1.0)
		for airport in GameData.airports:
			var x := 12.0 + (float(airport.lon) + 180.0) / 360.0 * (rect.size.x - 24.0)
			var y := 12.0 + (90.0 - float(airport.lat)) / 180.0 * (rect.size.y - 24.0)
			map.draw_circle(Vector2(x,y), 4.0, ACCENT)
			map.draw_string(ThemeDB.fallback_font, Vector2(x+6,y-5), airport.iata, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)
	)
	map_panel.add_child(map)
	_note("На карте отмечены аэропорты из локальной базы. Маршрутные дуги и движущиеся маркеры рейсов будут расширены в следующих итерациях.")
	for route in GameData.state.routes:
		_row(route.from + "  →  " + route.to, str(route.distance) + " км", true)

func _page_fleet() -> void:
	_section("МОЙ ФЛОТ", "%d воздушных судов" % GameData.state.aircraft.size())
	for plane in GameData.state.aircraft:
		var model := GameData.get_aircraft_model(plane.model_id)
		_card(model.name, plane.registration + "  •  " + plane.status, "Базирование: %s   |   Состояние: %d%%   |   Налёт: %d ч" % [plane.location, roundi(plane.condition), roundi(plane.hours)])
	_section("КАТАЛОГ САМОЛЁТОВ", "Покупка списывает стоимость с баланса")
	for model in GameData.aircraft_catalog:
		var row := VBoxContainer.new()
		_style_card(row)
		content.add_child(row)
		var title := Label.new()
		title.text = model.name
		title.add_theme_color_override("font_color", TEXT)
		title.add_theme_font_size_override("font_size", 15)
		row.add_child(title)
		var info := Label.new()
		info.text = "%s  •  %d мест  •  %s км  •  %d двиг." % [model.manufacturer, model.seats, model.range_km, model.engines]
		info.add_theme_color_override("font_color", MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var buy := Button.new()
		buy.text = "Купить  —  " + GameData.format_money(model.price)
		buy.pressed.connect(func():
			if GameData.buy_aircraft(model.id):
				_toast("Самолёт приобретён")
			else:
				_toast("Недостаточно средств")
			_refresh()
		)
		row.add_child(buy)

func _page_routes() -> void:
	_section("МАРШРУТНАЯ СЕТЬ", "Рейсы между реальными аэропортами из базы")
	for route in GameData.state.routes:
		_card(route.from + " → " + route.to, route.status + "  •  " + str(route.distance) + " км", "%d пассажиров  |  результат %s" % [route.passengers, GameData.format_money(route.profit)])
	_section("НОВЫЙ МАРШРУТ", "Выберите самолёт, находящийся в аэропорту отправления")
	var from := _option_picker("Откуда", _airport_options(), GameData.state.company.hub)
	var to := _option_picker("Куда", _airport_options(), "LHR")
	var planes := []
	for plane in GameData.state.aircraft:
		if plane.status == "На стоянке":
			planes.append({"label": plane.registration + " • " + plane.model_id + " • " + plane.location, "value": plane.id})
	var plane_picker := _option_picker("Самолёт", planes, planes[0].value if not planes.is_empty() else "")
	var price := SpinBox.new()
	price.min_value = 30
	price.max_value = 2500
	price.value = 180
	price.suffix = " $"
	content.add_child(price)
	var create := Button.new()
	create.text = "РАССЧИТАТЬ И ОТКРЫТЬ МАРШРУТ"
	create.pressed.connect(func():
		if from.get_item_count() == 0 or to.get_item_count() == 0 or plane_picker.get_item_count() == 0:
			_toast("Нет доступного самолёта или аэропорта")
			return
		var ok := GameData.create_route(from.get_item_metadata(from.selected), to.get_item_metadata(to.selected), plane_picker.get_item_metadata(plane_picker.selected), price.value)
		_toast("Маршрут открыт" if ok else "Не удалось открыть: проверьте дальность, базирование и состояние самолёта")
		_refresh()
	)
	content.add_child(create)

func _page_airports() -> void:
	_section("АЭРОПОРТЫ", "%d аэропортов в локальной базе" % GameData.airports.size())
	for airport in GameData.airports:
		_card(airport.name, airport.iata + " / " + airport.city + ", " + airport.country, "%d ВПП  •  координаты %.2f, %.2f" % [airport.runways, airport.lat, airport.lon])

func _page_finance() -> void:
	_section("ФИНАНСЫ", "Текущий денежный баланс")
	_metric_grid([["БАЛАНС",GameData.format_money(GameData.state.money)],["ОПЕРАЦИЙ",str(GameData.state.ledger.size())]])
	for item in GameData.state.ledger:
		_row("День %d • %s" % [item.day,item.label], GameData.format_money(item.amount), item.amount >= 0)

func _page_events() -> void:
	_section("СОБЫТИЯ", "Оперативная информация")
	_note("Случайные операционные события, погодные ограничения и рыночные колебания появятся в следующих этапах. Сейчас симуляция использует базовый расчёт рейса и обслуживания.")
	_note("Текущая скорость: " + ("Пауза" if GameData.paused else str(GameData.sim_speed) + "×"))

func _page_saves() -> void:
	_section("УПРАВЛЕНИЕ СОХРАНЕНИЯМИ", "Автосохранение и ручные слоты")
	_action("Сохранить слот 1", func(): _toast("Слот 1 сохранён" if GameData.save_game("slot_1") else "Ошибка сохранения"))
	_action("Сохранить слот 2", func(): _toast("Слот 2 сохранён" if GameData.save_game("slot_2") else "Ошибка сохранения"))
	_action("Загрузить слот 1", func(): _toast("Слот 1 загружен" if GameData.load_game("slot_1") else "Слот 1 не найден"); _refresh())
	_action("Экспортировать сохранение", _export_save)
	_action("Импортировать сохранение", _import_save)
	_action("Сохранить сейчас", func(): GameData.autosave(); _toast("Автосохранение выполнено"))
	_note("Последнее сохранение: " + str(GameData.state.get("last_saved","—")))

func _show_company_setup() -> void:
	for child in content.get_children():
		child.queue_free()
	_section("СОЗДАНИЕ АВИАКОМПАНИИ", "Ваша история начинается с небольшого стартового капитала")
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Название авиакомпании"
	name_input.text = "Toska Airways"
	content.add_child(name_input)
	var code_input := LineEdit.new()
	code_input.placeholder_text = "Код компании (2–3 символа)"
	code_input.text = "TS"
	content.add_child(code_input)
	var country_input := LineEdit.new()
	country_input.placeholder_text = "Страна регистрации"
	country_input.text = "Netherlands"
	content.add_child(country_input)
	var hub_picker := _option_picker("Главный аэропорт", _airport_options(), "AMS")
	var start := Button.new()
	start.text = "ОСНОВАТЬ АВИАКОМПАНИЮ"
	start.custom_minimum_size.y = 54
	start.pressed.connect(func():
		var company_name := name_input.text.strip_edges()
		var code := code_input.text.strip_edges()
		if company_name.is_empty() or code.length() < 2 or hub_picker.get_item_count() == 0:
			_toast("Заполните название, код и выберите хаб")
			return
		GameData.new_company(company_name, code.substr(0,3), country_input.text.strip_edges(), hub_picker.get_item_metadata(hub_picker.selected))
		page = "Обзор"
		_refresh()
	)
	content.add_child(start)
	_note("Стартовый капитал: $25 000 000. В игре уже доступен каталог самолётов, аэропорты, покупка флота, создание маршрутов и базовая финансовая симуляция.")

func _airport_options() -> Array:
	var result := []
	for a in GameData.airports:
		result.append({"label": a.iata + " — " + a.city + ", " + a.country, "value": a.iata})
	return result

func _option_picker(label_text: String, options: Array, preferred: String) -> OptionButton:
	var wrap := VBoxContainer.new()
	content.add_child(wrap)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", MUTED)
	wrap.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		picker.add_item(option.label)
		picker.set_item_metadata(picker.item_count - 1, option.value)
		if option.value == preferred:
			picker.select(picker.item_count - 1)
	wrap.add_child(picker)
	return picker

func _section(title_text: String, subtitle: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", ACCENT)
	content.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_color_override("font_color", MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(sub)

func _metric_grid(items: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for item in items:
		var panel := PanelContainer.new()
		_style_panel(panel)
		grid.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var label := Label.new()
		label.text = item[0]
		label.add_theme_color_override("font_color", MUTED)
		label.add_theme_font_size_override("font_size", 10)
		box.add_child(label)
		var value := Label.new()
		value.text = item[1]
		value.add_theme_color_override("font_color", TEXT)
		value.add_theme_font_size_override("font_size", 19)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(value)

func _card(title_text: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	_style_panel(panel)
	content.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	for pair in [[title_text, TEXT, 15], [subtitle, ACCENT, 12], [detail, MUTED, 11]]:
		var label := Label.new()
		label.text = pair[0]
		label.add_theme_color_override("font_color", pair[1])
		label.add_theme_font_size_override("font_size", pair[2])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)

func _row(left: String, right: String, positive: bool) -> void:
	var h := HBoxContainer.new()
	content.add_child(h)
	var l := Label.new()
	l.text = left
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_color_override("font_color", ACCENT if positive else Color("#ff8e83"))
	h.add_child(r)

func _note(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	content.add_child(label)

func _action(label_text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = label_text
	b.pressed.connect(callback)
	content.add_child(b)

func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(7)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)

func _style_card(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 5)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(7)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	box.add_theme_stylebox_override("panel", style)

func _style_button(button: Button, active: bool) -> void:
	button.add_theme_color_override("font_color", BG if active else TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT if active else PANEL_ALT
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 7
	normal.content_margin_right = 7
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	button.add_theme_stylebox_override("normal", normal)

func _toast(message: String) -> void:
	status_label.text = message
	await get_tree().create_timer(2.0).timeout
	_refresh_header()

func _export_save() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json", "AirlinesSim Save")
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(GameData.state, "\t"))
			file.close()
			_toast("Сохранение экспортировано")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(600, 420))

func _import_save() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json", "AirlinesSim Save")
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and int(parsed.get("version",0)) <= GameData.SAVE_VERSION and parsed.has("company"):
			GameData.state = parsed
			GameData.autosave()
			_toast("Сохранение импортировано")
			_refresh()
		else:
			_toast("Файл сохранения повреждён или несовместим")
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(600, 420))
