-- Add columns that existed on the Django models but were missed in 0001,
-- then seed real catalog data copied from the live Django database
-- (wast_wastetype / wast_bintype) so Phase 1 has real data to work with.

alter table public.waste_types add column if not exists description text;
alter table public.bin_types add column if not exists description text;
alter table public.bin_types add column if not exists is_active boolean not null default true;
alter table public.bin_types add column if not exists sort_order int not null default 0;

insert into public.waste_types (id, key, label, description, base_price, icon, color_hex, is_active, sort_order) overriding system value values
  (1, 'general', 'General Waste', 'Household and everyday waste', 20.00, 'delete_outline', '#757575', true, 1),
  (2, 'recyclable', 'Recyclable', 'Paper, plastic, glass and metal', 20.00, 'recycling', '#1565C0', true, 2),
  (3, 'organic', 'Organic / Compost', 'Food scraps and garden waste', 20.00, 'eco', '#2E7D32', true, 3),
  (4, 'hazardous', 'Hazardous', 'Chemicals, batteries and e-waste', 45.00, 'science_outlined', '#E65100', true, 4)
on conflict (id) do nothing;
select setval(pg_get_serial_sequence('public.waste_types', 'id'), (select max(id) from public.waste_types));

insert into public.bin_types (id, waste_type_id, name, display_name, price, description, is_active, sort_order) overriding system value values
  (1, 1, 'small', 'Small Bin', 20.00, 'Up to 20 litres — bags & small boxes', true, 1),
  (2, 1, 'medium', 'Medium Bin', 35.00, 'Up to 60 litres — medium bags & bulky items', true, 2),
  (3, 1, 'large', 'Large Bin', 55.00, 'Up to 120 litres — large household haul', true, 3),
  (4, 2, 'small', 'Small Bin', 18.00, 'Up to 20 litres of sorted recyclables', true, 1),
  (5, 2, 'medium', 'Medium Bin', 30.00, 'Up to 60 litres of sorted recyclables', true, 2),
  (6, 2, 'large', 'Large Bin', 45.00, 'Up to 120 litres of sorted recyclables', true, 3),
  (7, 3, 'small', 'Small Bin', 15.00, 'Up to 20 litres of organic / compost waste', true, 1),
  (8, 3, 'medium', 'Medium Bin', 25.00, 'Up to 60 litres of organic / compost waste', true, 2),
  (9, 3, 'large', 'Large Bin', 40.00, 'Up to 120 litres of organic / compost waste', true, 3),
  (10, 4, 'standard', 'Standard Pack', 55.00, 'Up to 10 kg — batteries, small chemicals', true, 1),
  (11, 4, 'large', 'Large Pack', 85.00, 'Up to 25 kg — e-waste, larger chemicals', true, 2),
  (12, 4, 'special', 'Special Disposal', 120.00, 'Bulk / special hazardous disposal', true, 3)
on conflict (id) do nothing;
select setval(pg_get_serial_sequence('public.bin_types', 'id'), (select max(id) from public.bin_types));
