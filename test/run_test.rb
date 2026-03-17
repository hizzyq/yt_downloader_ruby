#!/usr/bin/env ruby
# test/run_tests.rb - Запускатор всех тестов

require_relative "test_helper"
require_relative "downloader_test"

# Запуск всех тестов
success = TestCase.run_all

# Возвращаем код ошибки для CI/CD
exit(success ? 0 : 1)