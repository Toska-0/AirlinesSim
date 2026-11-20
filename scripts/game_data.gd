extends Node
## Persistent single-player simulation state. Save format is explicitly versioned.

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const AUTOSAVE_PATH := "user://autosave.json"
const AIRCRAFT_PATH := "res://data/aircraft.json"
const AIRPORTS_PATH := "res://data/airports.json"

var state: Dictionary = {}
var aircraft_catalog: Array = []
var airports: Array = []
var sim_speed: float = 1.0
var paused := false
var _accumulator := 0.0

func _ready() -> void:
	aircraft_catalog = _read_json(AIRCRAFT_PATH)
	airports = _read_json(AIRPORTS_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

func _read_json(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []

func new_company(company_name: String, code: String, country: String, hub_iata: String) -> void:
	state = {
		"version": SAVE_VERSION,
		"company": {"name": company_name, "code": code.to_upper(), "country": country, "hub": hub_iata, "reputation": 50.0, "level": 1, "xp": 0},
		"money": 45000000.0,
		"day": 1,
		"minute": 360,
		"aircraft": [],
		"routes": [],
		"ledger": [],
		"events": [],
		"last_saved": Time.get_datetime_string_from_system()
	}
	_save_state(AUTOSAVE_PATH)

func has_game() -> bool:
	return not state.is_empty() and state.has("company")

func buy_aircraft(model_id: String) -> bool:
	var model := get_aircraft_model(model_id)
	if model.is_empty() or not has_game():
		return false
	var price := float(model.get("price", 0))
	if float(state.money) < price:
		return false
	state.money = float(state.money) - price
	var serial: int = state.aircraft.size() + 1
	state.aircraft.append({
		"id": "AS-%03d" % serial,
		"model_id": model_id,
		"registration": "%s-%03d" % [state.company.code, serial],
		"condition": 100.0,
		"hours": 0.0,
		"status": "На стоянке",
		"location": state.company.hub,
		"route_id": "",
		"flight_progress": 0.0,
		"fuel": 100.0
	})
	_add_ledger("Покупка самолёта " + str(model.name), -price)
	return true

func create_route(from_iata: String, to_iata: String, aircraft_id: String, ticket_price: float) -> bool:
	if from_iata == to_iata or get_airport(from_iata).is_empty() or get_airport(to_iata).is_empty():
		return false
	for route in state.routes:
		if route["from"] == from_iata and route["to"] == to_iata:
			return false
	var plane_index := -1
	for i in state.aircraft.size():
		if state.aircraft[i].id == aircraft_id and state.aircraft[i].status == "На стоянке" and state.aircraft[i].location == from_iata:
			plane_index = i
			break
	if plane_index < 0:
		return false
	var a := get_airport(from_iata)
	var b := get_airport(to_iata)
	var distance := _distance_km(float(a.lat), float(a.lon), float(b.lat), float(b.lon))
	var model := get_aircraft_model(state.aircraft[plane_index].model_id)
	if distance > float(model.range_km) * 0.88:
		return false
	var route_id := "R-%03d" % (state.routes.size() + 1)
	state.routes.append({"id": route_id, "from": from_iata, "to": to_iata, "distance": roundi(distance), "aircraft_id": aircraft_id, "ticket_price": ticket_price, "status": "Запланирован", "passengers": 0, "profit": 0.0})
	state.aircraft[plane_index].status = "Подготовка к вылету"
	state.aircraft[plane_index].route_id = route_id
	return true

func advance_simulation(delta: float) -> void:
	if not has_game() or paused:
		return
	_accumulator += delta * sim_speed
	while _accumulator >= 1.0:
		_accumulator -= 1.0
		state.minute += 10
		if state.minute >= 1440:
			state.minute -= 1440
			state.day += 1
			_daily_costs()
		_process_flights(10.0)

func _process_flights(minutes: float) -> void:
	for plane in state.aircraft:
		if plane.status == "Подготовка к вылету":
			plane.status = "В полёте"
			for route in state.routes:
				if route.id == plane.route_id:
					route.status = "В полёте"
		elif plane.status == "В полёте":
			var route_data := {}
			for route in state.routes:
				if route.id == plane.route_id:
					route_data = route
					break
			if route_data.is_empty():
				plane.status = "Неисправен"
				continue
			var model := get_aircraft_model(plane.model_id)
			var flight_minutes := maxf(35.0, float(route_data.distance) / maxf(1.0, float(model.speed_kmh)) * 60.0)
			plane.flight_progress += minutes / flight_minutes
			plane.fuel = maxf(0.0, plane.fuel - minutes * float(model.fuel_per_hour) / 60.0 / 100.0)
			if plane.flight_progress >= 1.0:
				_complete_flight(plane, route_data, model)

func _complete_flight(plane: Dictionary, route: Dictionary, model: Dictionary) -> void:
	var demand := _estimate_demand(route)
	var seats := int(model.seats)
	var passengers := mini(seats, demand)
	var revenue := passengers * float(route.ticket_price)
	var flight_hours := float(route.distance) / maxf(1.0, float(model.speed_kmh))
	var fuel_cost := flight_hours * float(model.fuel_per_hour) * 0.9
	var airport_fees := 2200.0 + float(route.distance) * 0.8
	var maintenance := float(route.distance) * 1.15
	var profit := revenue - fuel_cost - airport_fees - maintenance
	state.money = float(state.money) + profit
	route.passengers = passengers
	route.profit = profit
	route.status = "Выполнен"
	plane.location = route.to
	plane.status = "На стоянке"
	plane.flight_progress = 0.0
	plane.route_id = ""
	plane.hours += float(route.distance) / float(model.speed_kmh)
	plane.condition = maxf(0.0, plane.condition - float(route.distance) / 18000.0)
	plane.fuel = 100.0
	_add_ledger("Рейс %s → %s (%d пассажиров)" % [route.from, route.to, passengers], profit)
	state.company.reputation = clampf(float(state.company.reputation) + (0.12 if profit > 0 else -0.2), 0.0, 100.0)
	state.company.xp += passengers
	route.status = "Готов к повторному вылету"

func _estimate_demand(route: Dictionary) -> int:
	var a := get_airport(route.from)
	var b := get_airport(route.to)
	var base := (float(a.population) + float(b.population)) / 18000.0
	var price_factor := clampf(160.0 / maxf(40.0, float(route.ticket_price)), 0.25, 1.8)
	var reputation_factor := 0.65 + float(state.company.reputation) / 140.0
	return maxi(0, roundi(base * price_factor * reputation_factor * randf_range(0.82, 1.18)))

func _daily_costs() -> void:
	var payroll := 0.0
	for plane in state.aircraft:
		var model := get_aircraft_model(plane.model_id)
		payroll += float(model.maintenance_daily)
		state.money -= float(model.maintenance_daily)
		plane.condition = maxf(0.0, plane.condition - 0.035)
	_add_ledger("Ежедневное обслуживание флота", -payroll)

func _add_ledger(label: String, amount: float) -> void:
	state.ledger.push_front({"day": int(state.day), "label": label, "amount": amount})
	if state.ledger.size() > 100:
		state.ledger.resize(100)

func get_aircraft_model(model_id: String) -> Dictionary:
	for model in aircraft_catalog:
		if model.id == model_id:
			return model
	return {}

func get_airport(iata: String) -> Dictionary:
	for airport in airports:
		if airport.iata == iata:
			return airport
	return {}

func format_money(value: float) -> String:
	var raw := str(absi(roundi(value)))
	var grouped := ""
	for i in raw.length():
		if i > 0 and (raw.length() - i) % 3 == 0:
			grouped += " "
		grouped += raw.substr(i, 1)
	return ("-$" if value < 0.0 else "$") + grouped

func save_game(slot: String = "autosave") -> bool:
	if not has_game():
		return false
	var path := SAVE_DIR.path_join(slot + ".json")
	return _save_state(path)

func _save_state(path: String) -> bool:
	state.last_saved = Time.get_datetime_string_from_system()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	return true

func load_game(slot: String = "autosave") -> bool:
	var path := SAVE_DIR.path_join(slot + ".json")
	if not FileAccess.file_exists(path) and slot == "autosave":
		path = AUTOSAVE_PATH
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	var version := int(parsed.get("version", 0))
	if version > SAVE_VERSION:
		return false
	state = parsed
	state.version = SAVE_VERSION
	return true

func autosave() -> void:
	if has_game():
		_save_state(AUTOSAVE_PATH)

func _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var r := 6371.0
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var h := sin(dp / 2.0) ** 2 + cos(p1) * cos(p2) * sin(dl / 2.0) ** 2
	return r * 2.0 * atan2(sqrt(h), sqrt(1.0 - h))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()
