-- АвтоРитм: схема, права, REST-функции и демонстрационные данные.
-- Выполнить один раз в SQL Editor нового проекта Supabase.
begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
create schema if not exists private;
revoke all on schema private from public;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null, email text not null unique,
  role text not null default 'client' check (role in ('admin','master','client')),
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key default gen_random_uuid(), "user" uuid not null unique references public.users(id),
  phone text not null default '', specialization text not null default '',
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.customers (
  id uuid primary key default gen_random_uuid(), name text not null, phone text not null,
  email text not null default '', account uuid unique references public.users(id), discount numeric not null default 0,
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.vehicles (
  id uuid primary key default gen_random_uuid(), customer uuid not null references public.customers(id),
  brand text not null, model text not null, plate text not null unique, vin text not null unique,
  year integer not null, mileage integer not null default 0,
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, description text not null default '',
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.services (
  id uuid primary key default gen_random_uuid(), name text not null, category uuid not null references public.categories(id),
  price numeric(12,2) not null, duration integer not null, description text not null default '',
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.parts (
  id uuid primary key default gen_random_uuid(), name text not null, sku text not null unique, manufacturer text not null,
  price numeric(12,2) not null, stock integer not null default 0,
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.bays (
  id uuid primary key default gen_random_uuid(), name text not null unique, kind text not null, equipment text not null default '',
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.orders (
  id uuid primary key default gen_random_uuid(), number text not null unique default '',
  vehicle uuid not null references public.vehicles(id), master uuid references public.users(id), bay uuid references public.bays(id),
  status text not null default 'new', starts_at timestamptz not null, ends_at timestamptz not null,
  complaint text not null, notes text not null default '', discount numeric not null default 0,
  labor_total numeric(12,2) not null default 0, parts_total numeric(12,2) not null default 0, total numeric(12,2) not null default 0,
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.order_services (
  id uuid primary key default gen_random_uuid(), "order" uuid not null references public.orders(id), service uuid not null references public.services(id),
  unit_price numeric(12,2) not null default 0, unique("order",service),
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.order_parts (
  id uuid primary key default gen_random_uuid(), "order" uuid not null references public.orders(id), part uuid not null references public.parts(id),
  quantity integer not null, unit_price numeric(12,2) not null default 0, unique("order",part),
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);
create table public.inspections (
  id uuid primary key default gen_random_uuid(), "order" uuid not null unique references public.orders(id), condition text not null,
  findings text not null, recommendations text not null default '', mileage integer not null,
  deleted_at timestamptz, created timestamptz not null default now(), updated timestamptz not null default now()
);

-- Explicit RLS activation for every API table.
alter table public.users enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.vehicles enable row level security;
alter table public.categories enable row level security;
alter table public.services enable row level security;
alter table public.parts enable row level security;
alter table public.bays enable row level security;
alter table public.orders enable row level security;
alter table public.order_services enable row level security;
alter table public.order_parts enable row level security;
alter table public.inspections enable row level security;

create function private.current_role() returns text language sql stable security definer set search_path = '' as $$
  select role from public.users where id = auth.uid() and deleted_at is null
$$;
create function private.owns_customer(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.customers where id=p_id and account=auth.uid())
$$;
create function private.owns_vehicle(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.vehicles v join public.customers c on c.id=v.customer where v.id=p_id and c.account=auth.uid())
$$;
create function private.owns_order(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.orders o join public.vehicles v on v.id=o.vehicle join public.customers c on c.id=v.customer where o.id=p_id and c.account=auth.uid())
$$;
create function private.editable_order(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.orders where id=p_id and status='new' and deleted_at is null) and private.owns_order(p_id)
$$;
grant usage on schema private to authenticated;
grant execute on function private.current_role(),private.owns_customer(uuid),private.owns_vehicle(uuid),private.owns_order(uuid),private.editable_order(uuid) to authenticated;

do $$ declare t text; staff text := '(select private.current_role()) in (''admin'',''master'')'; admin text := '(select private.current_role()) = ''admin''';
begin
  foreach t in array array['users','profiles','customers','vehicles','categories','services','parts','bays','orders','order_services','order_parts','inspections'] loop
    execute format('grant select,insert,update,delete on public.%I to authenticated',t);
    execute format('revoke all on public.%I from anon',t);
    execute format('create policy admin_all on public.%I for all to authenticated using (%s) with check (%s)',t,admin,admin);
  end loop;
  foreach t in array array['customers','vehicles','orders','order_parts','order_services','inspections'] loop
    execute format('create policy staff_all on public.%I for all to authenticated using (%s) with check (%s)',t,staff,staff);
  end loop;
  foreach t in array array['users','profiles','parts','bays'] loop
    execute format('create policy staff_read on public.%I for select to authenticated using (%s)',t,staff);
  end loop;
  foreach t in array array['categories','services'] loop
    execute format('create policy signed_read on public.%I for select to authenticated using ((select private.current_role()) is not null)',t);
  end loop;
end $$;
create policy self_read on public.users for select to authenticated using (id=auth.uid() and private.current_role() is not null);
create policy self_update on public.users for update to authenticated using (id=auth.uid() and private.current_role() is not null) with check (id=auth.uid());
create policy own_profile on public.profiles for select to authenticated using ("user"=auth.uid() and private.current_role() is not null);
create policy own_profile_edit on public.profiles for update to authenticated using ("user"=auth.uid() and private.current_role() is not null) with check ("user"=auth.uid());
create policy own_customer on public.customers for select to authenticated using (account=auth.uid() and private.current_role()='client');
create policy own_vehicle_read on public.vehicles for select to authenticated using (private.current_role()='client' and private.owns_customer(customer));
create policy own_vehicle_insert on public.vehicles for insert to authenticated with check (private.current_role()='client' and private.owns_customer(customer));
create policy own_vehicle_update on public.vehicles for update to authenticated using (private.current_role()='client' and private.owns_customer(customer)) with check (private.owns_customer(customer));
create policy own_order_read on public.orders for select to authenticated using (private.current_role()='client' and private.owns_vehicle(vehicle));
create policy own_order_insert on public.orders for insert to authenticated with check (private.current_role()='client' and private.owns_vehicle(vehicle));
create policy own_order_services on public.order_services for select to authenticated using (private.current_role()='client' and private.owns_order("order"));
create policy own_service_insert on public.order_services for insert to authenticated with check (private.current_role()='client' and private.editable_order("order"));
create policy own_service_update on public.order_services for update to authenticated using (private.current_role()='client' and private.editable_order("order")) with check (private.editable_order("order"));
create policy own_order_parts on public.order_parts for select to authenticated using (private.current_role()='client' and private.owns_order("order"));
create policy own_inspection on public.inspections for select to authenticated using (private.current_role()='client' and private.owns_order("order"));

create function private.field_error(p_field text,p_message text) returns void language plpgsql as $$
begin raise sqlstate 'PT422' using message='Проверьте поля формы.', detail=jsonb_build_object(p_field,p_message)::text; end $$;

create function private.rules(p_table text) returns jsonb language sql immutable set search_path='' as $$
select case p_table
when 'users' then '{"name":{"required":true,"length":100},"email":{"required":true,"format":"email","length":120},"role":{"values":["admin","master","client"]}}'::jsonb
when 'profiles' then '{"user":{"required":true,"target":"users"},"phone":{"length":20,"format":"phone"},"specialization":{"length":120}}'::jsonb
when 'customers' then '{"name":{"required":true,"length":100},"phone":{"required":true,"length":20,"format":"phone"},"email":{"length":120,"format":"email"},"account":{"target":"users"},"discount":{"min":0,"max":30}}'::jsonb
when 'vehicles' then '{"customer":{"required":true,"target":"customers"},"brand":{"required":true,"length":40},"model":{"required":true,"length":60},"plate":{"required":true,"length":12,"format":"plate"},"vin":{"required":true,"length":17,"format":"vin"},"year":{"required":true,"min":1950,"max":2100},"mileage":{"required":true,"min":0,"max":3000000}}'::jsonb
when 'categories' then '{"name":{"required":true,"length":80},"description":{"length":500}}'::jsonb
when 'services' then '{"name":{"required":true,"length":100},"category":{"required":true,"target":"categories"},"price":{"required":true,"min":0,"max":500000},"duration":{"required":true,"min":5,"max":1440},"description":{"length":1000}}'::jsonb
when 'parts' then '{"name":{"required":true,"length":100},"sku":{"required":true,"length":40},"manufacturer":{"required":true,"length":60},"price":{"required":true,"min":0,"max":1000000},"stock":{"required":true,"min":0,"max":100000}}'::jsonb
when 'bays' then '{"name":{"required":true,"length":60},"kind":{"values":["universal","diagnostics","tires"]},"equipment":{"length":500}}'::jsonb
when 'orders' then '{"vehicle":{"required":true,"target":"vehicles"},"master":{"target":"users"},"bay":{"target":"bays"},"status":{"values":["new","scheduled","in_progress","ready","closed","cancelled"]},"starts_at":{"required":true},"ends_at":{"required":true},"complaint":{"required":true,"length":2000},"notes":{"length":2000},"discount":{"min":0,"max":30}}'::jsonb
when 'order_services' then '{"order":{"required":true,"target":"orders"},"service":{"required":true,"target":"services"}}'::jsonb
when 'order_parts' then '{"order":{"required":true,"target":"orders"},"part":{"required":true,"target":"parts"},"quantity":{"required":true,"min":1,"max":1000}}'::jsonb
when 'inspections' then '{"order":{"required":true,"target":"orders"},"condition":{"values":["good","attention","critical"]},"findings":{"required":true,"length":3000},"recommendations":{"length":2000},"mileage":{"required":true,"min":0,"max":3000000}}'::jsonb
else null end
$$;

create function private.check_record() returns trigger language plpgsql set search_path=public,extensions as $$
declare data jsonb; previous jsonb:='{}'; rule record; value text; ref_ok boolean;
begin
  if tg_op='DELETE' then
    if private.current_role() is distinct from 'admin' and auth.uid() is not null then raise insufficient_privilege using message='Физическое удаление доступно только администратору.'; end if;
    if old.deleted_at is null then raise sqlstate 'PT409' using message='Сначала перенесите запись в архив.'; end if;
    return old;
  end if;
  new.updated:=now();
  if tg_op='UPDATE' then previous:=to_jsonb(old); end if;
  data:=to_jsonb(new);
  if auth.uid() is not null and private.current_role()='client' and tg_op='UPDATE' then
    if data->>'deleted_at' is distinct from previous->>'deleted_at' and tg_table_name<>'order_services' then raise insufficient_privilege using message='Изменять архив может сотрудник.'; end if;
    if tg_table_name='vehicles' and data->>'customer' is distinct from previous->>'customer' then raise insufficient_privilege using message='Нельзя менять владельца автомобиля.'; end if;
    if tg_table_name='profiles' and data->>'user' is distinct from previous->>'user' then raise insufficient_privilege; end if;
  end if;
  for rule in select e.key,e.value from jsonb_each(private.rules(tg_table_name)) e loop
    value:=data->>rule.key;
    if coalesce((rule.value->>'required')::boolean,false) and coalesce(btrim(value),'')='' then perform private.field_error(rule.key,'Обязательное поле'); end if;
    if rule.value ? 'length' and length(value)>(rule.value->>'length')::int then perform private.field_error(rule.key,'Не больше '||(rule.value->>'length')||' символов'); end if;
    if rule.value ? 'min' and (value::numeric < (rule.value->>'min')::numeric or value::numeric > (rule.value->>'max')::numeric or value in ('NaN','Infinity','-Infinity')) then perform private.field_error(rule.key,'Число выходит за допустимый диапазон'); end if;
    if rule.value ? 'values' and not coalesce((rule.value->'values') ? value,false) then perform private.field_error(rule.key,'Выберите значение из списка'); end if;
    if coalesce(value,'')<>'' then
      if rule.value->>'format'='email' and value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then perform private.field_error(rule.key,'Введите корректный email'); end if;
      if rule.value->>'format'='phone' and value !~ '^\+?[0-9 ()-]{10,20}$' then perform private.field_error(rule.key,'Введите корректный телефон'); end if;
      if rule.value->>'format'='vin' and value !~ '^[A-HJ-NPR-Z0-9]{17}$' then perform private.field_error(rule.key,'VIN: 17 букв и цифр, без I, O, Q'); end if;
      if rule.value->>'format'='plate' and value !~ '^[А-ЯA-Z0-9 -]{5,12}$' then perform private.field_error(rule.key,'Проверьте госномер'); end if;
      if rule.value ? 'target' and (tg_op='INSERT' or value is distinct from previous->>rule.key or (previous->>'deleted_at' is not null and data->>'deleted_at' is null)) then
        execute format('select exists(select 1 from public.%I where id=$1 and deleted_at is null)',rule.value->>'target') into ref_ok using value::uuid;
        if not ref_ok then perform private.field_error(rule.key,'Запись не найдена или находится в архиве'); end if;
      end if;
    end if;
  end loop;
  return new;
end $$;

create function private.guard_user() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' then
    if auth.uid() is not null and private.current_role() is distinct from 'admin' and (new.role is distinct from old.role or new.email is distinct from old.email) then raise insufficient_privilege using message='Недостаточно прав для изменения роли или email.'; end if;
    if new.id=auth.uid() and (new.role<>'admin' and old.role='admin' or new.deleted_at is not null) then raise sqlstate 'PT409' using message='Нельзя отключить или понизить свою учётную запись.'; end if;
    if old.role='admin' and old.deleted_at is null and (new.role<>'admin' or new.deleted_at is not null) and not exists(select 1 from public.users where role='admin' and deleted_at is null and id<>old.id) then raise sqlstate 'PT409' using message='В системе должен остаться активный администратор.'; end if;
  end if;
  return new;
end $$;
create trigger a_guard_user before update on public.users for each row execute function private.guard_user();

create function private.prepare_order() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_discount numeric; actor_role text:=private.current_role();
begin
  perform pg_advisory_xact_lock(88180426);
  if tg_op='INSERT' then
    new.number:='ЗН-'||upper(substr(replace(new.id::text,'-',''),1,10));
    select c.discount into owner_discount from public.customers c join public.vehicles v on v.customer=c.id where v.id=new.vehicle;
    new.discount:=coalesce(owner_discount,0);
    if actor_role='client' then new.status:='new'; new.master:=null; new.bay:=null; new.notes:=''; end if;
  end if;
  if new.ends_at<=new.starts_at or new.ends_at-new.starts_at>interval '24 hours' then perform private.field_error('ends_at','Окончание должно быть позже начала. Длительность — до 24 часов.'); end if;
  if new.master is not null and not exists(select 1 from public.users where id=new.master and role='master' and deleted_at is null) then perform private.field_error('master','Назначьте действующего мастера'); end if;
  if new.status in ('scheduled','in_progress','ready','closed') and (new.master is null or new.bay is null) then perform private.field_error('bay','Назначьте пост и мастера'); end if;
  if new.deleted_at is null and new.status not in ('closed','cancelled') and exists(
    select 1 from public.orders o where o.id<>new.id and o.deleted_at is null and o.status not in ('closed','cancelled') and o.starts_at<new.ends_at and o.ends_at>new.starts_at
      and (o.vehicle=new.vehicle or (new.bay is not null and o.bay=new.bay) or (new.master is not null and o.master=new.master))) then
    raise sqlstate 'PT409' using message='В это время автомобиль, мастер или пост уже заняты. Выберите другой интервал.';
  end if;
  select coalesce(sum(unit_price),0) into new.labor_total from public.order_services where "order"=new.id and deleted_at is null;
  select coalesce(sum(unit_price*quantity),0) into new.parts_total from public.order_parts where "order"=new.id and deleted_at is null;
  new.total:=round(new.labor_total*(1-new.discount/100)+new.parts_total,2);
  return new;
end $$;
create trigger a_prepare_order before insert or update on public.orders for each row execute function private.prepare_order();
create function private.prepare_line() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_table_name='order_services' then
    if tg_op='INSERT' or new.service is distinct from old.service then select price into new.unit_price from public.services where id=new.service; else new.unit_price:=old.unit_price; end if;
  else
    if tg_op='INSERT' or new.part is distinct from old.part then select price into new.unit_price from public.parts where id=new.part; else new.unit_price:=old.unit_price; end if;
  end if;
  return new;
end $$;
create function private.line_totals() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op<>'DELETE' then update public.orders set updated=now() where id=new."order"; end if;
  if tg_op='DELETE' or (tg_op='UPDATE' and old."order"<>new."order") then update public.orders set updated=now() where id=old."order"; end if;
  return null;
end $$;
create trigger a_prepare_line before insert or update on public.order_services for each row execute function private.prepare_line();
create trigger a_prepare_line before insert or update on public.order_parts for each row execute function private.prepare_line();
create trigger totals_changed after insert or update or delete on public.order_services for each row execute function private.line_totals();
create trigger totals_changed after insert or update or delete on public.order_parts for each row execute function private.line_totals();

create function private.ensure_services() returns trigger language plpgsql security definer set search_path='' as $$
declare oid uuid;
begin
  if tg_table_name='orders' then oid:=new.id; else oid:=coalesce(new."order",old."order"); end if;
  if exists(select 1 from public.orders where id=oid and deleted_at is null) and not exists(select 1 from public.order_services where "order"=oid and deleted_at is null) then perform private.field_error('services','Выберите хотя бы одну услугу'); end if;
  return null;
end $$;
create constraint trigger order_requires_services after insert or update on public.orders deferrable initially deferred for each row execute function private.ensure_services();
create constraint trigger order_requires_services after insert or update or delete on public.order_services deferrable initially deferred for each row execute function private.ensure_services();

create function private.prepare_vehicle() returns trigger language plpgsql set search_path='' as $$
begin
  new.plate:=upper(regexp_replace(new.plate,'\s','','g')); new.vin:=upper(new.vin);
  if new.year>extract(year from now())+1 then perform private.field_error('year','Год выпуска не может быть в будущем'); end if;
  return new;
end $$;
create trigger a_prepare_vehicle before insert or update on public.vehicles for each row execute function private.prepare_vehicle();

do $$ declare t text; begin
  foreach t in array array['users','profiles','customers','vehicles','categories','services','parts','bays','orders','order_services','order_parts','inspections'] loop
    execute format('create trigger z_validate before insert or update or delete on public.%I for each row execute function private.check_record()',t);
    execute format('create index on public.%I(deleted_at,created)',t);
  end loop;
end $$;
create index on public.orders(status,starts_at);
create index on public.orders(master,starts_at);
create index on public.vehicles(customer);

create function private.provision_account() returns trigger language plpgsql security definer set search_path='' as $$
declare app_role text:=coalesce(new.raw_app_meta_data->>'app_role','client');
begin
  if app_role not in ('admin','master','client') then app_role:='client'; end if;
  insert into public.users(id,name,email,role) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'name',''),split_part(new.email,'@',1)),100),new.email,app_role);
  insert into public.profiles("user") values(new.id);
  if app_role='client' then insert into public.customers(name,phone,email,account) values(left(coalesce(nullif(new.raw_user_meta_data->>'name',''),split_part(new.email,'@',1)),100),'+7 (000) 000-00-00',new.email,new.id); end if;
  return new;
end $$;
create trigger on_autoritm_signup after insert on auth.users for each row execute function private.provision_account();

-- Only the small role-check helpers can be called by authenticated sessions.
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_role(),private.owns_customer(uuid),private.owns_vehicle(uuid),private.owns_order(uuid),private.editable_order(uuid),private.rules(text),private.field_error(text,text) to authenticated;

create function private.check_collection(p_table text) returns void language plpgsql immutable set search_path='' as $$
begin if private.rules(p_table) is null then raise sqlstate 'PT404' using message='Неизвестный справочник.'; end if; end $$;

create function private.record_json(p_table text,p_data jsonb) returns jsonb language plpgsql stable set search_path='' as $$
declare expanded jsonb:='{}'; ids jsonb;
begin
  if p_data is null then return null; end if;
  case p_table
    when 'profiles' then expanded:=jsonb_build_object('user',private.one_record('users',p_data->>'user'));
    when 'customers' then expanded:=jsonb_build_object('account',private.one_record('users',p_data->>'account'));
    when 'vehicles' then expanded:=jsonb_build_object('customer',private.one_record('customers',p_data->>'customer'));
    when 'services' then expanded:=jsonb_build_object('category',private.one_record('categories',p_data->>'category'));
    when 'orders' then
      select coalesce(jsonb_agg(service order by created,id),'[]') into ids from public.order_services where "order"=(p_data->>'id')::uuid and deleted_at is null;
      p_data:=p_data||jsonb_build_object('services',ids);
      expanded:=jsonb_build_object('vehicle',private.one_record('vehicles',p_data->>'vehicle'),'master',private.one_record('users',p_data->>'master'),'bay',private.one_record('bays',p_data->>'bay'),'services',coalesce((select jsonb_agg(private.one_record('services',value#>>'{}')) from jsonb_array_elements(ids)),'[]'));
    when 'order_services' then expanded:=jsonb_build_object('order',private.one_record('orders',p_data->>'order'),'service',private.one_record('services',p_data->>'service'));
    when 'order_parts' then expanded:=jsonb_build_object('order',private.one_record('orders',p_data->>'order'),'part',private.one_record('parts',p_data->>'part'));
    when 'inspections' then expanded:=jsonb_build_object('order',private.one_record('orders',p_data->>'order'));
    else null;
  end case;
  return p_data||jsonb_build_object('expand',jsonb_strip_nulls(expanded));
end $$;
create function private.one_record(p_table text,p_id text) returns jsonb language plpgsql stable set search_path='' as $$
declare data jsonb;
begin
  if nullif(p_id,'') is null then return null; end if;
  perform private.check_collection(p_table);
  execute format('select to_jsonb(t) from public.%I t where id=$1',p_table) into data using p_id::uuid;
  return private.record_json(p_table,data);
end $$;
create function private.json_path(p_field text) returns text[] language plpgsql immutable set search_path='' as $$
declare segments text[]; path text[]:='{}'; i int;
begin
  if p_field !~ '^[a-z_]+(\.[a-z_]+){0,2}$' then raise sqlstate 'PT422' using message='Некорректное поле запроса.'; end if;
  segments:=string_to_array(p_field,'.');
  for i in 1..array_length(segments,1) loop
    if i<array_length(segments,1) then path:=path||array['expand']; end if;
    path:=path||array[segments[i]];
  end loop;
  return path;
end $$;
create function private.search_fields(p_table text) returns text[] language sql immutable set search_path='' as $$
select case p_table
 when 'orders' then array['number','complaint','vehicle.plate','vehicle.brand','vehicle.model','vehicle.customer.name']
 when 'vehicles' then array['brand','model','plate','vin','customer.name']
 when 'services' then array['name','description','category.name']
 when 'order_services' then array['order.number','service.name']
 when 'order_parts' then array['order.number','part.name','part.sku']
 when 'inspections' then array['order.number','findings','recommendations']
 when 'profiles' then array['user.name','phone','specialization']
 when 'customers' then array['name','phone','email']
 when 'parts' then array['name','sku','manufacturer']
 when 'bays' then array['name','equipment']
 when 'users' then array['name','email']
 else array['name','description'] end
$$;
create function public.list_records(p_collection text,p_query jsonb default '{}') returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare conditions text:='true'; searches text[]:='{}'; field text; item record; rule jsonb;
  ordering text; sort_key text; direction text:='asc'; amount int; page_number int; result jsonb;
begin
  perform private.check_collection(p_collection);
  if private.current_role() is null then raise insufficient_privilege using message='Требуется вход в систему.'; end if;
  amount:=greatest(1,least(coalesce((p_query->>'size')::int,10),200)); page_number:=greatest(1,least(coalesce((p_query->>'page')::int,1),100000));
  if coalesce(p_query->>'archive','active')='active' then conditions:=conditions||' and data->>''deleted_at'' is null';
  elsif p_query->>'archive'='archived' then conditions:=conditions||' and data->>''deleted_at'' is not null'; end if;
  if coalesce(p_query->>'search','')<>'' then
    foreach field in array private.search_fields(p_collection) loop
      searches:=searches||format('(data#>>%L)::text ilike %L escape ''\''',private.json_path(field), '%'||replace(replace(replace(p_query->>'search','\','\\'),'%','\%'),'_','\_')||'%');
    end loop;
    conditions:=conditions||' and ('||array_to_string(searches,' or ')||')';
  end if;
  for item in select key,value#>>'{}' as value from jsonb_each(coalesce(p_query->'filters','{}')) loop
    if coalesce(item.value,'')='' then continue; end if;
    if item.key in ('from','to') then
      field:=case when p_collection='orders' then 'starts_at' else 'created' end;
      conditions:=conditions||format(' and (data->>%L)::timestamptz %s %L::timestamptz',field,case when item.key='from' then '>=' else '<=' end,item.value);
    elsif private.rules(p_collection) ? item.key then
      rule:=private.rules(p_collection)->item.key;
      if rule ? 'min' then conditions:=conditions||format(' and (data->>%L)::numeric=%L::numeric',item.key,item.value);
      elsif rule ? 'target' or rule ? 'values' then conditions:=conditions||format(' and data->>%L=%L',item.key,item.value);
      else conditions:=conditions||format(' and position(lower(%L) in lower(coalesce(data->>%L,'''')))>0',item.value,item.key); end if;
    end if;
  end loop;
  sort_key:=coalesce(p_query->>'sort','-created');
  if left(sort_key,1)='-' then sort_key:=substr(sort_key,2); direction:='desc'; end if;
  if not(private.rules(p_collection) ? sort_key) and sort_key not in ('number','total','unit_price','created','updated') then sort_key:='created'; direction:='desc'; end if;
  rule:=private.rules(p_collection)->sort_key;
  ordering:=format('data->>%L',sort_key);
  if rule ? 'min' or sort_key in ('total','unit_price') then ordering:='('||ordering||')::numeric'; end if;
  ordering:=ordering||' '||direction||' nulls last,data->>''id''';
  execute format('with enriched as materialized (select private.record_json(%L,to_jsonb(t)) as data from public.%I t), filtered as (select data from enriched where %s), paged as (select data from filtered order by %s limit %s offset %s) select jsonb_build_object(''items'',coalesce((select jsonb_agg(data) from paged),''[]''::jsonb),''page'',%s,''totalItems'',(select count(*) from filtered),''totalPages'',ceil((select count(*) from filtered)::numeric/%s)::int)',p_collection,p_collection,conditions,ordering,amount,(page_number-1)*amount,page_number,amount) into result;
  return result;
end $$;
create function public.get_record(p_collection text,p_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare data jsonb;
begin data:=private.one_record(p_collection,p_id::text); if data is null then raise sqlstate 'PT404' using message='Запись не найдена или недоступна.'; end if; return data; end $$;

create function public.save_record(p_collection text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare columns text[]:='{}'; assignments text[]:='{}'; values_sql text[]:='{}'; field record; allowed jsonb; result_id uuid; service_id uuid; selected uuid[]; payload jsonb; type_name text;
begin
  perform private.check_collection(p_collection);
  if p_collection='users' then raise insufficient_privilege using message='Используйте управление учётными записями.'; end if;
  allowed:=private.rules(p_collection)||'{"deleted_at":{}}';
  payload:=p_data;
  if p_collection='orders' and (p_id is null or p_data ? 'services') then
    if jsonb_typeof(p_data->'services') is distinct from 'array' or jsonb_array_length(p_data->'services')=0 or jsonb_array_length(p_data->'services')>50 then perform private.field_error('services','Выберите от 1 до 50 услуг'); end if;
    select array_agg(distinct value::uuid) into selected from jsonb_array_elements_text(p_data->'services');
  end if;
  for field in select key,value from jsonb_each(p_data) loop
    if not(allowed ? field.key) then continue; end if;
    select format_type(a.atttypid,a.atttypmod) into type_name from pg_attribute a where a.attrelid=format('public.%I',p_collection)::regclass and a.attname=field.key and a.attnum>0;
    if type_name is null then continue; end if;
    if type_name='integer' and (field.value#>>'{}')::numeric<>trunc((field.value#>>'{}')::numeric) then perform private.field_error(field.key,'Введите целое число'); end if;
    if type_name in ('uuid','timestamp with time zone') and (field.value='""'::jsonb or field.value='null'::jsonb) then payload:=jsonb_set(payload,array[field.key],'null'); end if;
    columns:=columns||format('%I',field.key); values_sql:=values_sql||format('($1->>%L)::%s',field.key,type_name);
    assignments:=assignments||format('%I=($1->>%L)::%s',field.key,field.key,type_name);
  end loop;
  if p_id is null then
    execute format('insert into public.%I(%s) values(%s) returning id',p_collection,array_to_string(columns,','),array_to_string(values_sql,',')) into result_id using payload;
  else
    if cardinality(assignments)=0 then assignments:=array['updated=now()']; end if;
    execute format('update public.%I set %s where id=$2 returning id',p_collection,array_to_string(assignments,',')) into result_id using payload,p_id;
  end if;
  if result_id is null then raise sqlstate 'PT404' using message='Запись не найдена или недоступна.'; end if;
  if p_collection='orders' and selected is not null then
    update public.order_services set deleted_at=now() where "order"=result_id and not(service=any(selected)) and deleted_at is null;
    foreach service_id in array selected loop
      insert into public.order_services("order",service) values(result_id,service_id) on conflict("order",service) do update set deleted_at=null;
    end loop;
  end if;
  return private.one_record(p_collection,result_id::text);
exception
  when unique_violation then raise sqlstate 'PT409' using message='Такая запись уже существует. Проверьте уникальные поля.';
  when foreign_key_violation then raise sqlstate 'PT409' using message='Связанная запись отсутствует или используется в другой записи.';
  when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow then raise sqlstate 'PT422' using message='Некорректный формат числа, даты или ссылки.';
  when not_null_violation then raise sqlstate 'PT422' using message='Заполните обязательные поля.';
end $$;

create function public.manage_account(p_id uuid default null,p_data jsonb default '{}',p_delete boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid; password text:=p_data->>'password'; input_name text:=btrim(p_data->>'name'); input_email text:=lower(btrim(p_data->>'email')); input_role text:=p_data->>'role';
begin
  if private.current_role() is distinct from 'admin' then raise insufficient_privilege using message='Управление учётными записями доступно администратору.'; end if;
  if p_delete then
    if p_id=auth.uid() or not exists(select 1 from public.users where id=p_id and deleted_at is not null) then raise sqlstate 'PT409' using message='Сначала перенесите учётную запись в архив.'; end if;
    delete from auth.users where id=p_id; return '{}'::jsonb;
  end if;
  if p_id is null then
    if coalesce(length(password),0)<10 or length(password)>72 then perform private.field_error('password','Пароль должен содержать 10–72 символа'); end if;
    if coalesce(input_name,'')='' then perform private.field_error('name','Обязательное поле'); end if;
    if input_email is null or input_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then perform private.field_error('email','Введите корректный email'); end if;
    if input_role not in ('admin','master','client') or input_role is null then perform private.field_error('role','Выберите роль'); end if;
    uid:=gen_random_uuid();
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
    values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',input_email,extensions.crypt(password,extensions.gen_salt('bf')),now(),jsonb_build_object('provider','email','providers',array['email'],'app_role',input_role),jsonb_build_object('name',input_name),now(),now(),'','','','');
    insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at) values(gen_random_uuid(),uid::text,uid,jsonb_build_object('sub',uid::text,'email',input_email,'email_verified',true),'email',now(),now());
  else
    uid:=p_id;
    if p_data ? 'name' then update public.users set name=input_name where id=uid; end if;
    if p_data ? 'email' then update auth.users set email=input_email where id=uid; update public.users set email=input_email where id=uid; end if;
    if p_data ? 'role' then update public.users set role=input_role where id=uid; end if;
    if p_data ? 'deleted_at' then update public.users set deleted_at=nullif(p_data->>'deleted_at','')::timestamptz where id=uid; end if;
    if nullif(password,'') is not null then
      if length(password)<10 or length(password)>72 then perform private.field_error('password','Пароль должен содержать 10–72 символа'); end if;
      update auth.users set encrypted_password=extensions.crypt(password,extensions.gen_salt('bf')),updated_at=now() where id=uid;
      delete from auth.sessions where user_id=uid;
    end if;
  end if;
  return private.one_record('users',uid::text);
exception when unique_violation then raise sqlstate 'PT409' using message='Этот email уже используется.';
  when foreign_key_violation then raise sqlstate 'PT409' using message='На учётную запись есть ссылки. Удалите связанные записи или оставьте её в архиве.';
end $$;
create function public.delete_record(p_collection text,p_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare found_id uuid;
begin
  perform private.check_collection(p_collection);
  if p_collection='users' then perform public.manage_account(p_id,'{}',true); return; end if;
  execute format('delete from public.%I where id=$1 returning id',p_collection) into found_id using p_id;
  if found_id is null then raise sqlstate 'PT404' using message='Запись не найдена или недоступна.'; end if;
exception when foreign_key_violation then raise sqlstate 'PT409' using message='На запись есть ссылки. Удалите связанные записи или оставьте её в архиве.';
end $$;

revoke all on function public.list_records(text,jsonb),public.get_record(text,uuid),public.save_record(text,uuid,jsonb),public.manage_account(uuid,jsonb,boolean),public.delete_record(text,uuid) from public,anon;
grant execute on function public.list_records(text,jsonb),public.get_record(text,uuid),public.save_record(text,uuid,jsonb),public.manage_account(uuid,jsonb,boolean),public.delete_record(text,uuid) to authenticated;
revoke all on function private.record_json(text,jsonb),private.one_record(text,text),private.check_collection(text),private.search_fields(text),private.json_path(text) from public,anon;
grant execute on function private.record_json(text,jsonb),private.one_record(text,text),private.check_collection(text),private.search_fields(text),private.json_path(text) to authenticated;
notify pgrst,'reload schema';

do $$
declare person jsonb; entry jsonb; uid uuid; cid uuid; car_id uuid; service_id uuid; order_id uuid;
  customers uuid[]; cars uuid[]:='{}'; categories uuid[]:='{}'; services uuid[]:='{}'; parts uuid[]:='{}'; bays uuid[]:='{}';
  i int:=0; start_time timestamptz; states text[]:=array['scheduled','in_progress','ready','new','closed','scheduled','new','closed','cancelled','ready','scheduled','new'];
begin
  for person in select value from jsonb_array_elements('[
    {"id":"10000000-0000-0000-0000-000000000001","email":"admin@autoritm.local","name":"Алексей Волков","role":"admin","password":"Admin12345!"},
    {"id":"10000000-0000-0000-0000-000000000002","email":"master@autoritm.local","name":"Дмитрий Соколов","role":"master","password":"Master12345!"},
    {"id":"10000000-0000-0000-0000-000000000003","email":"client@autoritm.local","name":"Иван Петров","role":"client","password":"Client12345!"}]'::jsonb) loop
    uid:=(person->>'id')::uuid;
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
    values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',person->>'email',extensions.crypt(person->>'password',extensions.gen_salt('bf')),now(),jsonb_build_object('provider','email','providers',array['email'],'app_role',person->>'role'),jsonb_build_object('name',person->>'name'),now(),now(),'','','','');
    insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at)
    values(gen_random_uuid(),uid::text,uid,jsonb_build_object('sub',uid::text,'email',person->>'email','email_verified',true),'email',now(),now());
    update public.profiles set phone='+7 (999) 123-45-67',specialization=case when person->>'role'='master' then 'Диагностика и ходовая часть' else '' end where "user"=uid;
  end loop;
  update public.customers set discount=10,phone='+7 (999) 123-45-67' where account='10000000-0000-0000-0000-000000000003';
  select array[id] into customers from public.customers where account='10000000-0000-0000-0000-000000000003';
  for entry in select value from jsonb_array_elements('[
    {"name":"Мария Кузнецова","phone":"+7 (916) 234-56-78","email":"maria@example.com","discount":5},
    {"name":"Андрей Смирнов","phone":"+7 (925) 345-67-89","discount":0},
    {"name":"Елена Орлова","phone":"+7 (903) 456-78-90","discount":15}]'::jsonb) loop
    insert into public.customers(name,phone,email,discount) values(entry->>'name',entry->>'phone',coalesce(entry->>'email',''),(entry->>'discount')::numeric) returning id into cid;
    customers:=customers||cid;
  end loop;
  for entry in select value from jsonb_array_elements('[
    ["Toyota","Camry","А123ВС777","JTNB11HK003012345",2020,68000],
    ["Kia","Rio","М456КЕ799","Z94C241BBLR123456",2021,42000],
    ["Volkswagen","Polo","О789РТ750","XW8ZZZ61ZLG123456",2019,91000],
    ["Hyundai","Solaris","Е321АК197","Z94K241CBJR654321",2018,112000],
    ["Lada","Vesta","К654МН777","XTA218000L0123456",2022,28500]]'::jsonb) loop
    insert into public.vehicles(customer,brand,model,plate,vin,year,mileage) values(customers[1+i%4],entry->>0,entry->>1,entry->>2,entry->>3,(entry->>4)::int,(entry->>5)::int) returning id into car_id;
    cars:=cars||car_id;i:=i+1;
  end loop;
  for entry in select value from jsonb_array_elements('["Техническое обслуживание","Диагностика","Ходовая часть","Шиномонтаж"]'::jsonb) loop
    insert into public.categories(name) values(entry#>>'{}') returning id into cid; categories:=categories||cid;
  end loop;
  for entry in select value from jsonb_array_elements('[
    ["Замена масла и фильтра",1,1800,45],["Плановое ТО",1,6500,120],["Компьютерная диагностика",2,2500,60],["Диагностика подвески",2,1500,30],
    ["Замена тормозных колодок",3,3200,90],["Развал-схождение",3,3800,60],["Шиномонтаж R16",4,3600,60],["Балансировка колёс",4,2000,45]]'::jsonb) loop
    insert into public.services(name,category,price,duration) values(entry->>0,categories[(entry->>1)::int],(entry->>2)::numeric,(entry->>3)::int) returning id into service_id;services:=services||service_id;
  end loop;
  for entry in select value from jsonb_array_elements('[
    ["Масло моторное 5W-30, 4 л","OIL-5W30-4","Lukoil",3900,24],["Фильтр масляный","FLT-TOY-01","MANN",850,32],
    ["Колодки тормозные передние","BRK-KIA-02","TRW",4200,8],["Фильтр воздушный","FLT-AIR-03","Bosch",1200,15]]'::jsonb) loop
    insert into public.parts(name,sku,manufacturer,price,stock) values(entry->>0,entry->>1,entry->>2,(entry->>3)::numeric,(entry->>4)::int) returning id into cid;parts:=parts||cid;
  end loop;
  for entry in select value from jsonb_array_elements('[["Пост 01","universal"],["Пост 02","universal"],["Диагностика","diagnostics"],["Шиномонтаж","tires"]]'::jsonb) loop
    insert into public.bays(name,kind,equipment) values(entry->>0,entry->>1,'Профильное оборудование, инструментальная тележка') returning id into cid;bays:=bays||cid;
  end loop;
  for i in 0..11 loop
    start_time:=(date_trunc('day',now() at time zone 'Europe/Moscow') at time zone 'Europe/Moscow')+interval '9 hours'+(i/4)*interval '1 day'+(i%4)*interval '2 hours';
    insert into public.orders(vehicle,master,bay,status,starts_at,ends_at,complaint)
    values(cars[1+i%5],'10000000-0000-0000-0000-000000000002',bays[1+i%4],states[i+1],start_time,start_time+interval '1 hour',
      (array['Плановое обслуживание, замена расходников','Шум при торможении, проверить колодки','Проверить подвеску перед дальней поездкой','Вибрация на скорости выше 90 км/ч'])[1+i%4]) returning id into order_id;
    insert into public.order_services("order",service) values(order_id,services[1+i%8]);
    if i=1 then insert into public.order_parts("order",part,quantity) values(order_id,parts[1],1); end if;
    if i=2 then insert into public.inspections("order",condition,findings,recommendations,mileage) values(order_id,'attention','Небольшой износ передних тормозных колодок.','Замена колодок через 5 000 км.',91000); end if;
  end loop;
end $$;

commit;
