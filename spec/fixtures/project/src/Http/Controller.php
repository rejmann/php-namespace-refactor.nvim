<?php

namespace App\Http;

use App\Foo\Bar;

class Controller
{
    public function __construct(private Bar $bar)
    {
    }

    public function index(): string
    {
        return $this->bar->run();
    }
}
