-- Seed file for societies and units
INSERT INTO societies (id, name, address) VALUES
('d3b07384-d113-4c07-b3c4-95e206000001', 'Orchid Gardens', '123 Park Avenue, New York'),
('d3b07384-d113-4c07-b3c4-95e206000002', 'Pinewood Crest', '456 Forest Road, Seattle')
ON CONFLICT (id) DO NOTHING;

INSERT INTO units (id, society_id, block, unit_number) VALUES
('a0f7e462-8172-466d-96ef-e95e78000001', 'd3b07384-d113-4c07-b3c4-95e206000001', 'A', '101'),
('a0f7e462-8172-466d-96ef-e95e78000002', 'd3b07384-d113-4c07-b3c4-95e206000001', 'A', '102'),
('a0f7e462-8172-466d-96ef-e95e78000003', 'd3b07384-d113-4c07-b3c4-95e206000001', 'B', '201'),
('a0f7e462-8172-466d-96ef-e95e78000004', 'd3b07384-d113-4c07-b3c4-95e206000002', 'X', '501')
ON CONFLICT (society_id, block, unit_number) DO NOTHING;
