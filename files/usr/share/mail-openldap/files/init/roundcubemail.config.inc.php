<?php

$config = array();
$config['db_dsnw'] = 'mysql://%DB_USER:%DB_PASSWORD@%DB_HOST/%DB';
$config['default_host'] = 'localhost';
$config['smtp_server'] = 'localhost';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['support_url'] = '%SUPPORT_URL';
$config['product_name'] = '%PRODUCT_NAME';
$config['des_key'] = 'rcmail-!24ByteDESkey*Str';
$config['plugins'] = array(
    'archive',
    'zipdownload',
);
$config['skin'] = 'larry';

