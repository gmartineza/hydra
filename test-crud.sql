-- CRUD Operations Test Script
-- Connect through ProxySQL: mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db

USE demo_db;

-- ============================================
-- CREATE Operations
-- ============================================
SELECT '=== CREATE Operations ===' AS '';

-- Insert new products
INSERT INTO products (name, description, price, stock_quantity) VALUES
('Tablet', '10-inch Android tablet', 299.99, 80),
('Smartphone', 'Latest model smartphone', 699.99, 60);

SELECT 'Products created' AS 'Status';
SELECT * FROM products ORDER BY id DESC LIMIT 2;

-- Create a new order
INSERT INTO orders (product_id, quantity, total_price, customer_name, status) VALUES
(1, 2, 1999.98, 'John Doe', 'pending');

SELECT 'Order created' AS 'Status';
SELECT * FROM orders ORDER BY id DESC LIMIT 1;

-- ============================================
-- READ Operations
-- ============================================
SELECT '=== READ Operations ===' AS '';

-- Read all products
SELECT 'All Products:' AS '';
SELECT id, name, price, stock_quantity FROM products;

-- Read specific product
SELECT 'Product with ID 1:' AS '';
SELECT * FROM products WHERE id = 1;

-- Read orders with product details (JOIN)
SELECT 'Orders with Product Details:' AS '';
SELECT o.id, o.customer_name, p.name AS product_name, o.quantity, o.total_price, o.status
FROM orders o
JOIN products p ON o.product_id = p.id;

-- ============================================
-- UPDATE Operations
-- ============================================
SELECT '=== UPDATE Operations ===' AS '';

-- Update product price
UPDATE products SET price = 949.99 WHERE id = 1;
SELECT 'Product price updated' AS 'Status';
SELECT id, name, price FROM products WHERE id = 1;

-- Update stock quantity
UPDATE products SET stock_quantity = stock_quantity - 2 WHERE id = 1;
SELECT 'Stock quantity updated' AS 'Status';
SELECT id, name, stock_quantity FROM products WHERE id = 1;

-- Update order status
UPDATE orders SET status = 'completed' WHERE id = 1;
SELECT 'Order status updated' AS 'Status';
SELECT id, customer_name, status FROM orders WHERE id = 1;

-- ============================================
-- DELETE Operations
-- ============================================
SELECT '=== DELETE Operations ===' AS '';

-- Delete an order
DELETE FROM orders WHERE id = 1;
SELECT 'Order deleted' AS 'Status';
SELECT COUNT(*) AS 'Remaining Orders' FROM orders;

-- Delete a product (if no orders reference it)
-- DELETE FROM products WHERE id = 6;
-- SELECT 'Product deleted' AS 'Status';

-- ============================================
-- Verification: Check data on all nodes
-- ============================================
SELECT '=== Data Verification ===' AS '';
SELECT 'Total Products:' AS '', COUNT(*) AS count FROM products;
SELECT 'Total Orders:' AS '', COUNT(*) AS count FROM orders;

