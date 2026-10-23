<?php

namespace App\Foo;

class Bar
{
    public function __construct(private Helper $helper)
    {
    }

    public function run(): string
    {
        return $this->helper->help();
    }
}
