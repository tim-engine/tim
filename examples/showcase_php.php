<?php
// Tim Engine — PHP native extension showcase
// Run with: php83 -d extension=build/tim_php.so examples/showcase_php.php
if (!extension_loaded('tim')) {
  fwrite(STDERR, "tim extension not loaded. Run with: php83 -d extension=build/tim_php.so examples/showcase_php.php\n");
  exit(1);
}

init("templates", "storage", __DIR__);

$data = json_encode(["meta" => ["title" => "PHP Showcase"]]);

echo "=== Index with layout ===\n";
echo render("index", $data) . "\n";

echo "=== Error standalone ===\n";
echo renderView("error", $data) . "\n";
