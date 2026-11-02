-- Run in a disposable database after setup.sql. Every mutation rolls back.
begin;
create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %',label; end if; raise notice 'OK: %',label; end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ declare page jsonb; row jsonb; category_id uuid;
begin
  page:=public.list_records('orders','{}');
  perform pg_temp.assert_true((page->>'totalItems')::int=12 and jsonb_array_length(page->'items')=10,'server pagination');
  page:=public.list_records('orders','{"filters":{"status":"scheduled"},"sort":"starts_at"}');
  perform pg_temp.assert_true((page->>'totalItems')::int=3,'status filter');
  page:=public.list_records('orders','{"search":"Toyota"}');
  perform pg_temp.assert_true((page->>'totalItems')::int>0,'expanded relation search');
  page:=public.list_records('orders','{"search":"\" OR true --"}');
  perform pg_temp.assert_true((page->>'totalItems')::int=0,'search injection is literal text');
  row:=public.save_record('categories',null,'{"name":"Тестовая категория"}'); category_id:=(row->>'id')::uuid;
  row:=public.save_record('categories',category_id,'{"description":"Обновлено"}');
  perform pg_temp.assert_true(row->>'description'='Обновлено','CRUD update');
  begin perform public.delete_record('categories',category_id); raise exception 'deletion should fail'; exception when sqlstate 'PT409' then null; end;
  perform public.save_record('categories',category_id,jsonb_build_object('deleted_at',now()));
  page:=public.list_records('categories','{"archive":"archived"}');
  perform pg_temp.assert_true((page->>'totalItems')::int=1,'logical deletion');
  perform public.save_record('categories',category_id,'{"deleted_at":""}');
  row:=public.get_record('categories',category_id); perform pg_temp.assert_true(row->>'deleted_at' is null,'restore');
  perform public.save_record('categories',category_id,jsonb_build_object('deleted_at',now()));
  perform public.delete_record('categories',category_id);
  begin perform public.get_record('categories',category_id); raise exception 'deleted row should not exist'; exception when sqlstate 'PT404' then null; end;
  begin perform public.save_record('categories',null,'{"name":""}'); raise exception 'required should fail'; exception when sqlstate 'PT422' then null; end;
  perform pg_temp.assert_true(true,'field validation returns 422');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare page jsonb; car uuid; service uuid; part uuid; item jsonb; oid uuid; expected numeric;
begin
  page:=public.list_records('customers','{}');
  perform pg_temp.assert_true((page->>'totalItems')::int=1,'client sees only their customer record');
  page:=public.list_records('vehicles','{}');
  perform pg_temp.assert_true((page->>'totalItems')::int=2,'client sees only their vehicles');
  car:=(page->'items'->0->>'id')::uuid;
  page:=public.list_records('services','{}');service:=(page->'items'->0->>'id')::uuid;expected:=(page->'items'->0->>'price')::numeric*0.9;
  begin perform public.manage_account(null,'{"name":"Подмена","role":"admin","email":"bad@example.com","password":"Password123!"}'); raise exception 'role guard should fail'; exception when insufficient_privilege then null; end;
  begin update public.users set role='admin' where id=auth.uid(); raise exception 'self escalation should fail'; exception when insufficient_privilege then null; end;
  begin perform public.save_record('services',service,'{"price":1}'); raise exception 'reference mutation should fail'; exception when sqlstate 'PT404' then null; end;
  perform pg_temp.assert_true(true,'role escalation and reference write denied');
  item:=public.save_record('orders',null,jsonb_build_object('vehicle',car,'services',jsonb_build_array(service),'starts_at',now()+interval '10 days','ends_at',now()+interval '10 days 1 hour','status','closed','complaint','Тестовая запись','total',1,'discount',30));
  oid:=(item->>'id')::uuid;
  perform pg_temp.assert_true(item->>'status'='new' and (item->>'discount')::numeric=10 and (item->>'total')::numeric=round(expected,2),'client order and server quote');
  begin perform public.save_record('orders',null,jsonb_build_object('vehicle',car,'services',jsonb_build_array(service),'starts_at',now()+interval '10 days','ends_at',now()+interval '10 days 1 hour','complaint','Пересечение')); raise exception 'overlap should fail'; exception when sqlstate 'PT409' then null; end;
  perform pg_temp.assert_true(true,'overlapping vehicle booking denied');
  begin perform public.save_record('orders',null,jsonb_build_object('vehicle',car,'services','[]'::jsonb,'starts_at',now()+interval '11 days','ends_at',now()+interval '11 days 1 hour','complaint','Пусто')); raise exception 'empty services should fail'; exception when sqlstate 'PT422' then null; end;
  perform pg_temp.assert_true(true,'at least one related service is required');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ declare oid uuid; pid uuid; item jsonb; base numeric; price numeric;
begin
  select id,total into oid,base from public.orders where complaint='Тестовая запись';
  select id,parts.price into pid,price from public.parts limit 1;
  item:=public.save_record('order_parts',null,jsonb_build_object('order',oid,'part',pid,'quantity',2,'unit_price',1));
  item:=public.get_record('orders',oid);
  perform pg_temp.assert_true((item->>'parts_total')::numeric=2*price and (item->>'total')::numeric=base+2*price,'material snapshots and total calculation');
end $$;
do $$ declare u uuid; profile_id uuid; customer_id uuid; vehicle_id uuid; category_id uuid; service_id uuid; part_id uuid; bay_id uuid; order_id uuid; line_id uuid; material_id uuid; inspection_id uuid;
  item jsonb; target record; ids jsonb;
begin
  item:=public.manage_account(null,'{"name":"Тестовый мастер","email":"crud-test@example.com","role":"master","password":"Password12345!"}');u:=(item->>'id')::uuid;
  select id into profile_id from public.profiles where "user"=u;
  perform public.save_record('profiles',profile_id,jsonb_build_object('deleted_at',now()));perform public.delete_record('profiles',profile_id);
  item:=public.save_record('profiles',null,jsonb_build_object('user',u,'phone','+7 (999) 123-45-67'));profile_id:=(item->>'id')::uuid;
  item:=public.save_record('customers',null,'{"name":"Тестовый клиент","phone":"+7 (999) 765-43-21","discount":5}');customer_id:=(item->>'id')::uuid;
  item:=public.save_record('vehicles',null,jsonb_build_object('customer',customer_id,'brand','Тест','model','Автомобиль','plate','ТЕСТ123','vin','TEST1234567890123','year',2020,'mileage',0));vehicle_id:=(item->>'id')::uuid;
  item:=public.save_record('categories',null,'{"name":"CRUD-категория"}');category_id:=(item->>'id')::uuid;
  item:=public.save_record('services',null,jsonb_build_object('name','CRUD-услуга','category',category_id,'price',100,'duration',30));service_id:=(item->>'id')::uuid;
  item:=public.save_record('parts',null,'{"name":"CRUD-запчасть","sku":"CRUD-001","manufacturer":"Тест","price":50,"stock":10}');part_id:=(item->>'id')::uuid;
  item:=public.save_record('bays',null,'{"name":"CRUD-пост","kind":"universal"}');bay_id:=(item->>'id')::uuid;
  item:=public.save_record('orders',null,jsonb_build_object('vehicle',vehicle_id,'master',u,'bay',bay_id,'services',jsonb_build_array(service_id),'starts_at',now()+interval '40 days','ends_at',now()+interval '40 days 1 hour','status','scheduled','complaint','CRUD-проверка'));order_id:=(item->>'id')::uuid;
  select id into line_id from public.order_services where "order"=order_id;
  perform public.save_record('order_services',line_id,jsonb_build_object('deleted_at',now()));perform public.delete_record('order_services',line_id);
  item:=public.save_record('order_services',null,jsonb_build_object('order',order_id,'service',service_id));line_id:=(item->>'id')::uuid;
  item:=public.save_record('order_parts',null,jsonb_build_object('order',order_id,'part',part_id,'quantity',2));material_id:=(item->>'id')::uuid;
  item:=public.save_record('inspections',null,jsonb_build_object('order',order_id,'condition','good','findings','Исправно','mileage',50000));inspection_id:=(item->>'id')::uuid;
  ids:=jsonb_build_object('users',u,'profiles',profile_id,'customers',customer_id,'vehicles',vehicle_id,'categories',category_id,'services',service_id,'parts',part_id,'bays',bay_id,'orders',order_id,'order_services',line_id,'order_parts',material_id,'inspections',inspection_id);
  for target in select key,value#>>'{}' as value from jsonb_each(ids) loop
    if target.key='users' then
      perform public.manage_account(target.value::uuid,'{"name":"Изменённый мастер"}');
      perform public.manage_account(target.value::uuid,jsonb_build_object('deleted_at',now()));
      perform public.manage_account(target.value::uuid,'{"deleted_at":null}');
    else
      perform public.save_record(target.key,target.value::uuid,'{}');
      perform public.save_record(target.key,target.value::uuid,jsonb_build_object('deleted_at',now()));
      perform public.save_record(target.key,target.value::uuid,'{"deleted_at":null}');
    end if;
    item:=public.get_record(target.key,target.value::uuid);
    perform pg_temp.assert_true(item->>'deleted_at' is null,'CRUD and restore: '||target.key);
  end loop;
  for target in select value as name from unnest(array['inspections','order_parts','order_services','orders','bays','parts','services','categories','vehicles','customers','profiles','users']) value loop
    if target.name='users' then perform public.manage_account(u,jsonb_build_object('deleted_at',now()));
    else perform public.save_record(target.name,(ids->>target.name)::uuid,jsonb_build_object('deleted_at',now())); end if;
    perform public.delete_record(target.name,(ids->>target.name)::uuid);
  end loop;
  perform pg_temp.assert_true(true,'physical deletion of all 12 entities');
end $$;
set constraints all immediate;
rollback;
